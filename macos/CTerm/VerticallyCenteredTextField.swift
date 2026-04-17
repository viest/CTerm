import AppKit

final class VerticallyCenteredTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBezeled = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

func makeSettingsTextFieldContainer(for textField: NSTextField, width: CGFloat? = nil, height: CGFloat = 24) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 4
    container.layer?.borderColor = AppTheme.border.cgColor
    container.layer?.borderWidth = 1
    container.layer?.backgroundColor = AppTheme.bgTertiary.cgColor
    container.translatesAutoresizingMaskIntoConstraints = false
    container.setContentHuggingPriority(.defaultLow, for: .horizontal)
    container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    container.addSubview(textField)

    textField.translatesAutoresizingMaskIntoConstraints = false

    var constraints = [
        container.heightAnchor.constraint(equalToConstant: height),
        textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
        textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ]

    if let width {
        constraints.append(container.widthAnchor.constraint(equalToConstant: width))
    }

    NSLayoutConstraint.activate(constraints)
    return container
}
