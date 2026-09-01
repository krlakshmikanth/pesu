import AppKit

enum PesuTheme {
    static let paper = NSColor(red: 0.965, green: 0.963, blue: 0.945, alpha: 1)
    static let sidebar = NSColor(red: 0.925, green: 0.935, blue: 0.91, alpha: 1)
    static let ink = NSColor(red: 0.11, green: 0.125, blue: 0.11, alpha: 1)
    static let muted = NSColor(red: 0.43, green: 0.46, blue: 0.43, alpha: 1)
    static let line = NSColor(red: 0.84, green: 0.85, blue: 0.82, alpha: 1)
    static let coral = NSColor(red: 0.94, green: 0.36, blue: 0.24, alpha: 1)
    static let green = NSColor(red: 0.23, green: 0.62, blue: 0.40, alpha: 1)
    static let dark = NSColor(red: 0.075, green: 0.087, blue: 0.076, alpha: 1)
}

final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        target = self
        action = #selector(runAction)
        actionHandler = handler
    }

    @objc private func runAction() { actionHandler?() }
}

final class ActionSwitch: NSSwitch {
    var actionHandler: ((Bool) -> Void)?

    convenience init(isOn: Bool, handler: @escaping (Bool) -> Void) {
        self.init(frame: .zero)
        state = isOn ? .on : .off
        target = self
        action = #selector(runAction)
        actionHandler = handler
    }

    @objc private func runAction() { actionHandler?(state == .on) }
}

final class ClickableLabel: NSTextField {
    var clickHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

func clickablePathLabel(_ text: String, handler: @escaping () -> Void) -> ClickableLabel {
    let field = ClickableLabel(labelWithString: text)
    field.textColor = .linkColor
    field.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
    field.maximumNumberOfLines = 3
    field.lineBreakMode = .byCharWrapping
    field.cell?.wraps = true
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.clickHandler = handler
    field.setAccessibilityRole(.button)
    field.setAccessibilityLabel("Open recordings folder in Finder")
    field.toolTip = "Open in Finder"
    return field
}

final class ActionTextField: NSTextField {
    var actionHandler: (() -> Void)?

    convenience init(string: String, handler: @escaping () -> Void) {
        self.init(string: string)
        target = self
        action = #selector(runAction)
        actionHandler = handler
    }

    @objc private func runAction() { actionHandler?() }
}

final class KeyableSheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class ActionPopUpButton: NSPopUpButton {
    var actionHandler: ((String) -> Void)?

    convenience init(options: [MicrophoneOption], selectedID: String, handler: @escaping (String) -> Void) {
        self.init(frame: .zero, pullsDown: false)
        for option in options {
            addItem(withTitle: option.name)
            itemArray.last?.representedObject = option.id
        }
        if let selected = itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            select(selected)
        }
        target = self
        action = #selector(runAction)
        actionHandler = handler
    }

    convenience init(pets: [PetChoice], selected: PetChoice, handler: @escaping (PetChoice) -> Void) {
        self.init(frame: .zero, pullsDown: false)
        for pet in pets {
            addItem(withTitle: pet.displayName)
            itemArray.last?.representedObject = pet.rawValue
        }
        if let selectedItem = itemArray.first(where: { ($0.representedObject as? String) == selected.rawValue }) {
            select(selectedItem)
        }
        target = self
        action = #selector(runAction)
        actionHandler = { id in
            guard let pet = PetChoice(rawValue: id) else { return }
            handler(pet)
        }
    }

    convenience init(options: [(id: String, title: String)], selectedID: String, handler: @escaping (String) -> Void) {
        self.init(frame: .zero, pullsDown: false)
        for option in options {
            addItem(withTitle: option.title)
            itemArray.last?.representedObject = option.id
        }
        if let selected = itemArray.first(where: { ($0.representedObject as? String) == selectedID }) {
            select(selected)
        }
        target = self
        action = #selector(runAction)
        actionHandler = handler
    }

    @objc private func runAction() {
        guard let id = selectedItem?.representedObject as? String else { return }
        actionHandler?(id)
    }
}

extension NSView {
    func setBackground(_ color: NSColor, cornerRadius: CGFloat = 0) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = cornerRadius
    }
}

func label(
    _ text: String,
    size: CGFloat = 12,
    weight: NSFont.Weight = .regular,
    color: NSColor = PesuTheme.ink,
    serif: Bool = false,
    lines: Int = 1
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.textColor = color
    field.font = serif
        ? (NSFont(name: "New York", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight))
        : NSFont.systemFont(ofSize: size, weight: weight)
    field.maximumNumberOfLines = lines
    field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    if lines != 1 {
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}

func kicker(_ text: String) -> NSTextField {
    let value = label(text, size: 10, weight: .bold, color: PesuTheme.coral)
    value.alignment = .left
    return value
}

func separator() -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.contentViewMargins = .zero
    box.translatesAutoresizingMaskIntoConstraints = false
    return box
}

func vertical(_ views: [NSView], spacing: CGFloat = 0) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func horizontal(_ views: [NSView], spacing: CGFloat = 0) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

func flexibleSpace() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}
