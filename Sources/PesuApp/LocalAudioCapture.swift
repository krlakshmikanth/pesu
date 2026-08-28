import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

private let pesuAudioIOProc: AudioDeviceIOProc = { _, _, inputData, _, _, _, clientData in
    guard let clientData else { return noErr }
    let capture = Unmanaged<CoreAudioDeviceStream>.fromOpaque(clientData).takeUnretainedValue()
    return capture.consume(inputData)
}

private final class CoreAudioDeviceStream: @unchecked Sendable {
    enum StreamError: LocalizedError {
        case format(OSStatus)
        case formatUnavailable
        case createIO(OSStatus)
        case startIO(OSStatus)

        var errorDescription: String? {
            switch self {
            case .format(let status): "Pēsu could not read the audio-device format (\(status))."
            case .formatUnavailable: "The audio device did not provide a recordable format."
            case .createIO(let status): "Pēsu could not create the audio stream (\(status))."
            case .startIO(let status): "Pēsu could not start the audio stream (\(status))."
            }
        }
    }

    private let processingQueue: DispatchQueue
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private var writer: AVAudioFile?
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init(label: String = "com.pesu.audio-device") {
        processingQueue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func start(
        deviceID: AudioObjectID,
        url: URL,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        stop()

        let format = try Self.inputFormat(deviceID: deviceID)
        writer = try AVAudioFile(
            forWriting: url,
            settings: Self.fileSettings(for: format),
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        self.deviceID = deviceID
        self.format = format
        self.onBuffer = onBuffer

        var newIOProcID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcID(
            deviceID,
            pesuAudioIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &newIOProcID
        )
        guard status == noErr, let newIOProcID else {
            resetState()
            throw StreamError.createIO(status)
        }
        ioProcID = newIOProcID

        status = AudioDeviceStart(deviceID, newIOProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, newIOProcID)
            ioProcID = nil
            resetState()
            throw StreamError.startIO(status)
        }
    }

    func stop() {
        if deviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(deviceID, ioProcID)
            AudioDeviceDestroyIOProcID(deviceID, ioProcID)
        }
        ioProcID = nil
        processingQueue.sync {}
        resetState()
    }

    fileprivate func consume(_ inputData: UnsafePointer<AudioBufferList>?) -> OSStatus {
        guard let inputData, let format, let buffer = Self.copy(inputData, format: format) else { return noErr }
        processingQueue.async { [weak self] in
            try? self?.writer?.write(from: buffer)
            self?.onBuffer?(buffer)
        }
        return noErr
    }

    private func resetState() {
        writer = nil
        format = nil
        onBuffer = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private static func inputFormat(deviceID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { throw StreamError.format(status) }
        var streamIDs = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streamIDs)
        guard status == noErr else { throw StreamError.format(status) }

        for streamID in streamIDs {
            address = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyDirection,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var direction: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            status = AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &direction)
            guard status == noErr else { continue }
            guard direction == 1 else { continue }

            address = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var description = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            status = AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &description)
            guard status == noErr else { continue }
            if description.mChannelsPerFrame > 0,
               description.mSampleRate > 0,
               let format = AVAudioFormat(streamDescription: &description) {
                return format
            }
        }
        throw StreamError.formatUnavailable
    }

    private static func fileSettings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 128_000
        ]
    }

    private static func copy(
        _ inputData: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sources = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard !sources.isEmpty else { return nil }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = sources
            .filter { $0.mData != nil && $0.mDataByteSize > 0 }
            .map { Int($0.mDataByteSize) / bytesPerFrame }
            .min() ?? 0
        guard frameCount > 0,
              let copy = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return nil }
        copy.frameLength = AVAudioFrameCount(frameCount)

        let destinations = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sources.count == destinations.count else { return nil }
        for index in sources.indices {
            guard let sourceData = sources[index].mData,
                  let destinationData = destinations[index].mData else { return nil }
            let byteCount = min(Int(sources[index].mDataByteSize), Int(destinations[index].mDataByteSize))
            memcpy(destinationData, sourceData, byteCount)
            destinations[index].mDataByteSize = UInt32(byteCount)
        }
        return copy
    }
}

final class CoreAudioTapCapture: @unchecked Sendable {
    enum TapError: LocalizedError {
        case createTap(OSStatus)
        case createAggregate(OSStatus)
        case configureAggregate(OSStatus)
        case configureEngine(OSStatus)

        var errorDescription: String? {
            switch self {
            case .createTap(let status): "Pēsu could not start Apple system-audio capture (\(status))."
            case .createAggregate(let status): "Pēsu could not create its private audio route (\(status))."
            case .configureAggregate(let status): "Pēsu could not attach the system-audio tap (\(status))."
            case .configureEngine(let status): "Pēsu could not open its private audio route (\(status))."
            }
        }
    }

    private let stream = CoreAudioDeviceStream(label: "com.pesu.system-audio")
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)

    func start(url: URL, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        stop()

        let outputDeviceID = try defaultOutputDeviceID()
        let outputDeviceUID = try audioObjectString(
            id: outputDeviceID,
            selector: kAudioDevicePropertyDeviceUID
        )
        let description = CATapDescription(
            processes: [],
            deviceUID: outputDeviceUID,
            stream: 0
        )
        description.name = "Pēsu System Audio"
        description.isPrivate = true
        description.isProcessRestoreEnabled = true
        description.muteBehavior = .unmuted
        description.isExclusive = true

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw TapError.createTap(status) }
        tapID = newTapID

        let tapUID = description.uuid.uuidString
        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUID,
            kAudioSubTapDriftCompensationKey: true
        ]
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pēsu Private System Audio",
            kAudioAggregateDeviceUIDKey: "com.lattelabs.pesu.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [tapEntry],
            kAudioAggregateDeviceTapAutoStartKey: false
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr else {
            cleanupHardware()
            throw TapError.createAggregate(status)
        }
        aggregateID = newAggregateID

        do {
            try stream.start(deviceID: aggregateID, url: url, onBuffer: onBuffer)
        } catch {
            cleanupHardware()
            throw error
        }
    }

    func stop() {
        stream.stop()
        cleanupHardware()
    }

    private func cleanupHardware() {
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func audioObjectString(id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { throw TapError.configureAggregate(status) }
        return value as String
    }

    private func defaultOutputDeviceID() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw TapError.configureAggregate(status)
        }
        return deviceID
    }

}

final class MicrophoneCapture: @unchecked Sendable {
    enum MicrophoneError: LocalizedError {
        case deviceUnavailable
        case configureDevice(OSStatus)
        case configureEngine(OSStatus)

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable: "The selected microphone is unavailable. Choose another microphone in Settings."
            case .configureDevice(let status): "Pēsu could not open the selected microphone (\(status)). Choose another microphone in Settings."
            case .configureEngine(let status): "Pēsu could not start microphone recording (\(status))."
            }
        }
    }

    private let stream = CoreAudioDeviceStream(label: "com.pesu.microphone")

    func start(
        deviceID: String?,
        url: URL,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        let selectedDeviceID = try Self.resolveAudioDeviceID(uid: deviceID)
            ?? Self.resolveAudioDeviceID(uid: nil)
        guard let selectedDeviceID else {
            throw MicrophoneError.deviceUnavailable
        }
        try stream.start(deviceID: selectedDeviceID, url: url, onBuffer: onBuffer)
    }

    func stop() {
        stream.stop()
    }

    private static func resolveAudioDeviceID(uid: String?) throws -> AudioObjectID? {
        if let uid {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            var status = AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size
            )
            guard status == noErr else { throw MicrophoneError.configureDevice(status) }
            var devices = [AudioObjectID](
                repeating: kAudioObjectUnknown,
                count: Int(size) / MemoryLayout<AudioObjectID>.size
            )
            status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &devices
            )
            guard status == noErr else { throw MicrophoneError.configureDevice(status) }
            return devices.first { audioDeviceUID($0) == uid }
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultID
        )
        guard status == noErr else { throw MicrophoneError.configureDevice(status) }
        return defaultID == kAudioObjectUnknown ? nil : defaultID
    }

    private static func audioDeviceUID(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value as String : nil
    }

}
