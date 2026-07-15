import AppKit

/// A full-width caution strip shown below the tab bar whenever the active
/// project is a clone (copy-on-write fork). It reminds the user that a clone's
/// working copy is disposable: uncommitted changes vanish when the clone is
/// removed, so durable work must be committed + pushed to origin or landed
/// back into the source branch.
///
/// Recreated on every `rebuildSurfaceNodeView()` (so it appears/disappears as
/// the active project switches), it reads `ZTheme.current` at init like the
/// other content-area chrome (`HibernationPlaceholderView`). Uses the semantic
/// `yellow` = attention token — depth is surface + border, never shadow.
@MainActor
final class CloneWarningBanner: NSView {

    static let height: CGFloat = 26

    override init(frame: NSRect) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = ZTheme.current.bg2Color.cgColor

        // 2pt yellow accent bar down the leading edge.
        let accentBar = NSView()
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = ZTheme.current.yellowColor.cgColor
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)

        // 1pt hairline separating the banner from the terminal below.
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = ZTheme.current.borderColor.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                             accessibilityDescription: "Clone warning")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        icon.contentTintColor = ZTheme.current.yellowColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithAttributedString: Self.message())
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 2),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not supported") }

    /// Bold lead-in ("Clone (copy-on-write).") + regular guidance, so the
    /// warning reads as one prose sentence in the content area's system font.
    private static func message() -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "Clone (copy-on-write). ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: ZTheme.current.fgColor,
            ])
        result.append(NSAttributedString(
            string: "Commit and push to origin, or merge back into the source branch — uncommitted changes are lost when this clone is removed.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: ZTheme.current.fg2Color,
            ]))
        return result
    }
}
