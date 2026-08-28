import AVFoundation
import CoreMedia
import Foundation

enum AudioBufferConversion {
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ) else { return nil }
        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard requiredSize >= MemoryLayout<AudioBufferList>.size else { return nil }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let sourceList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        let sources = UnsafeMutableAudioBufferListPointer(sourceList)
        let destinations = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        guard sources.count == destinations.count else { return nil }

        for index in sources.indices {
            guard let sourceData = sources[index].mData,
                  let destinationData = destinations[index].mData else { return nil }
            let byteCount = min(Int(sources[index].mDataByteSize), Int(destinations[index].mDataByteSize))
            memcpy(destinationData, sourceData, byteCount)
            destinations[index].mDataByteSize = UInt32(byteCount)
        }
        return pcmBuffer
    }
}
