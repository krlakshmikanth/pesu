import AppKit

@MainActor
final class PetWindowController: NSWindowController, NSWindowDelegate {
    private static let windowSize = NSSize(width: 132, height: 154)
    private static let positionXKey = "pesu.pets.windowOriginX"
    private static let positionYKey = "pesu.pets.windowOriginY"

    private let model: AppModel
    private var spriteView: PetSpriteView!
    private var activityLabel: NSTextField!
    private var renderedPet: PetChoice?
    private var isHovering = false
    private var isClickAnimating = false
    private var clickAnimationTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "Pēsu pet"
        super.init(window: panel)
        panel.delegate = self
        installContent()
        restorePosition()
        modelDidChange()
    }

    required init?(coder: NSCoder) { nil }

    deinit { clickAnimationTask?.cancel() }

    func showIfEnabled() {
        guard model.arePetsEnabled else { return }
        window?.orderFrontRegardless()
    }

    func modelDidChange() {
        guard let panel = window else { return }
        if !model.arePetsEnabled {
            panel.orderOut(nil)
            return
        }
        if renderedPet != model.selectedPet {
            installContent()
        }
        updatePresentedActivity()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func windowDidMove(_ notification: Notification) {
        guard let origin = window?.frame.origin else { return }
        UserDefaults.standard.set(Double(origin.x), forKey: Self.positionXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: Self.positionYKey)
    }

    private func installContent() {
        guard let panel = window else { return }
        let interactionView = FloatingPetInteractionView()
        interactionView.translatesAutoresizingMaskIntoConstraints = false
        interactionView.onHoverChanged = { [weak self] hovering in
            self?.isHovering = hovering
            self?.updatePresentedActivity()
        }
        interactionView.onClick = { [weak self] in self?.playClickAnimation() }
        interactionView.onDragEnded = { [weak self] in
            guard let self else { return }
            self.windowDidMove(Notification(name: NSWindow.didMoveNotification))
        }

        let sprite = PetSpriteView(pet: model.selectedPet, activity: presentedActivity)
        let activityText = label(presentedActivity.displayName, size: 9, weight: .semibold, color: .white)
        activityText.alignment = .center
        let activityPill = horizontal([activityText])
        activityPill.edgeInsets = NSEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
        activityPill.setBackground(NSColor.black.withAlphaComponent(0.58), cornerRadius: 10)

        interactionView.addSubview(sprite)
        interactionView.addSubview(activityPill)
        panel.contentView = interactionView
        NSLayoutConstraint.activate([
            sprite.centerXAnchor.constraint(equalTo: interactionView.centerXAnchor),
            sprite.topAnchor.constraint(equalTo: interactionView.topAnchor),
            sprite.widthAnchor.constraint(equalToConstant: 112),
            sprite.heightAnchor.constraint(equalToConstant: 121),
            activityPill.centerXAnchor.constraint(equalTo: interactionView.centerXAnchor),
            activityPill.topAnchor.constraint(equalTo: sprite.bottomAnchor, constant: -1),
            activityPill.bottomAnchor.constraint(lessThanOrEqualTo: interactionView.bottomAnchor),
            interactionView.widthAnchor.constraint(equalToConstant: Self.windowSize.width),
            interactionView.heightAnchor.constraint(equalToConstant: Self.windowSize.height)
        ])
        interactionView.setAccessibilityElement(true)
        interactionView.setAccessibilityLabel("Floating \(model.selectedPet.displayName) pet. Drag to move; click to play.")
        spriteView = sprite
        activityLabel = activityText
        renderedPet = model.selectedPet
    }

    private var presentedActivity: PetActivity {
        if isClickAnimating { return .transcriptionComplete }
        if isHovering { return .complete }
        return model.petActivity
    }

    private func updatePresentedActivity() {
        let activity = presentedActivity
        spriteView?.show(activity: activity)
        activityLabel?.stringValue = activity.displayName
        spriteView?.setAccessibilityLabel("\(model.selectedPet.displayName) pet · \(activity.displayName)")
    }

    private func playClickAnimation() {
        clickAnimationTask?.cancel()
        isClickAnimating = true
        updatePresentedActivity()
        clickAnimationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.isClickAnimating = false
            self.updatePresentedActivity()
        }
    }

    private func restorePosition() {
        guard let panel = window else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.positionXKey) != nil,
           defaults.object(forKey: Self.positionYKey) != nil {
            let savedOrigin = NSPoint(
                x: defaults.double(forKey: Self.positionXKey),
                y: defaults.double(forKey: Self.positionYKey)
            )
            let savedFrame = NSRect(origin: savedOrigin, size: Self.windowSize)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) {
                panel.setFrameOrigin(savedOrigin)
                return
            }
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - Self.windowSize.width - 24,
            y: visibleFrame.minY + 24
        ))
    }
}

private final class FloatingPetInteractionView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?
    private var dragStartPointer: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var hasDragged = false

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        dragStartPointer = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        hasDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPointer, let dragStartWindowOrigin else { return }
        let pointer = NSEvent.mouseLocation
        let delta = NSPoint(x: pointer.x - dragStartPointer.x, y: pointer.y - dragStartPointer.y)
        if abs(delta.x) > 3 || abs(delta.y) > 3 { hasDragged = true }
        window?.setFrameOrigin(NSPoint(
            x: dragStartWindowOrigin.x + delta.x,
            y: dragStartWindowOrigin.y + delta.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        if hasDragged { onDragEnded?() }
        else { onClick?() }
        dragStartPointer = nil
        dragStartWindowOrigin = nil
        hasDragged = false
    }
}
