import AppKit

final class PetSpriteView: NSView {
    private static let columns = 8
    private static let rows = 9

    private let pet: PetChoice
    private let spritesheet: NSImage?
    private var activity: PetActivity
    private var frameIndex = 0
    private var timer: Timer?

    init(pet: PetChoice, activity: PetActivity) {
        self.pet = pet
        self.activity = activity
        spritesheet = Self.loadSpritesheet(for: pet)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        updateAccessibilityLabel()
        startAnimationTimer()
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    override var isOpaque: Bool { false }

    func show(activity: PetActivity) {
        guard self.activity != activity else { return }
        self.activity = activity
        frameIndex = 0
        updateAccessibilityLabel()
        startAnimationTimer()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let spritesheet else { return }

        let cellWidth = spritesheet.size.width / CGFloat(Self.columns)
        let cellHeight = spritesheet.size.height / CGFloat(Self.rows)
        let source = NSRect(
            x: CGFloat(frameIndex) * cellWidth,
            y: spritesheet.size.height - CGFloat(activity.animation.row + 1) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        spritesheet.draw(
            in: bounds,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func startAnimationTimer() {
        timer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let timer = Timer(timeInterval: activity.animation.frameDuration, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.activity.animation.frameCount
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel("\(pet.displayName) pet · \(activity.displayName)")
    }

    private static func loadSpritesheet(for pet: PetChoice) -> NSImage? {
        let appURL = Bundle.main.url(
            forResource: pet.rawValue,
            withExtension: "webp",
            subdirectory: "Pets"
        )
        let moduleURL = Bundle.module.url(
            forResource: pet.rawValue,
            withExtension: "webp",
            subdirectory: "Pets"
        )
        return (appURL ?? moduleURL).flatMap(NSImage.init(contentsOf:))
    }
}
