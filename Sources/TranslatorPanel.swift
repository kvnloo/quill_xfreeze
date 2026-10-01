import Cocoa

/// The live translation window: what was said on top, what it means below.
///
/// Made from the same materials as the dictation panel so the two read as one
/// app. Unlike that panel it takes clicks — it stays open to be read, dragged
/// and pointed at another language — but it never takes focus, so the call or
/// the video underneath keeps the keyboard.
final class TranslatorPanel {

    enum Layout: String {
        case both
        case translationOnly
    }

    enum Activity {
        case listening      // audio flowing, socket open
        case connecting     // waiting on the socket, or reconnecting
        case stopped        // not capturing — an error, or a permission missing
    }

    struct Line {
        let text: String
        let isCurrent: Bool
        let isDraft: Bool
    }

    var onClose: () -> Void = {}
    var onCopy: () -> Void = {}
    var onToggleLayout: () -> Void = {}
    var sourceMenu: () -> NSMenu = { NSMenu() }
    var targetMenu: () -> NSMenu = { NSMenu() }

    private var panel: NSPanel?
    private let root = PanelView()

    var isVisible: Bool { panel?.isVisible ?? false }
    var windowNumber: Int? { panel?.windowNumber }

    /// The panel's own pixels as the window server composited them, for the
    /// self-test. A process may capture its own windows without Screen Recording.
    func snapshotPNG() -> Data? {
        guard let panel, panel.isVisible else { return nil }
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
           !Self.isBlank(image) {
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
        // A locked or sleeping display composites nothing, and the window server
        // hands back black. Draw the views themselves over a stand-in backdrop.
        return renderOffscreenPNG()
    }

    private static func isBlank(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return true }
        for index in stride(from: 0, to: pixels.count, by: 4)
        where pixels[index] != 0 || pixels[index + 1] != 0 || pixels[index + 2] != 0 {
            return false
        }
        return true
    }

    private func renderOffscreenPNG() -> Data? {
        root.layoutSubtreeIfNeeded()
        let bounds = root.bounds
        guard let layerRep = root.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        root.cacheDisplay(in: bounds, to: layerRep)

        let margin: CGFloat = 24
        let size = NSSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        let scale = CGFloat(layerRep.pixelsWide) / bounds.width
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: out) else { return nil }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.43, blue: 0.55, alpha: 1),
                   ending: NSColor(calibratedRed: 0.70, green: 0.62, blue: 0.58, alpha: 1))?
            .draw(in: NSRect(origin: .zero, size: size), angle: -35)
        layerRep.draw(in: NSRect(x: margin, y: margin, width: bounds.width, height: bounds.height))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:])
    }

    func show() {
        let panel = ensurePanel()
        panel.setFrame(initialFrame(), display: true)
        panel.orderFrontRegardless()
        root.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            root.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            root.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    func setLayout(_ layout: Layout) {
        root.layoutMode = layout
        guard let panel else { return }
        var frame = panel.frame
        let height = root.preferredHeight
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    /// Kept out of screen shares and recordings unless asked otherwise — the
    /// person on the other end of the call does not need to watch it.
    func setHiddenFromCapture(_ hidden: Bool) {
        ensurePanel().sharingType = hidden ? .none : .readOnly
    }

    func setActivity(_ activity: Activity) { root.setActivity(activity) }
    func setElapsed(_ seconds: TimeInterval) { root.setElapsed(seconds) }
    func setLevel(_ level: Float) { root.setLevel(level) }
    func setSource(_ title: String) { root.setSource(title, menu: true) }
    /// A moment's message where the source name sits — "Copied", "Reconnecting…".
    func flash(_ message: String) { root.setSource(message, menu: false) }
    func setHeard(_ languageName: String?) { root.setHeard(languageName) }
    func setTarget(_ languageName: String) { root.setTarget(languageName) }

    /// Shown in place of the translation while there is nothing to translate,
    /// or when something needs fixing. The action makes the message clickable.
    func setNotice(_ message: String?, action: (title: String, run: () -> Void)? = nil) {
        root.setNotice(message, action: action)
    }

    func render(originals: [Line], translations: [Line]) {
        root.render(originals: originals, translations: translations)
    }

    // MARK: Window

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: root.preferredHeight),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = root
        self.panel = panel

        root.onClose = { [weak self] in self?.onClose() }
        root.onCopy = { [weak self] in self?.onCopy() }
        root.onToggleLayout = { [weak self] in self?.onToggleLayout() }
        root.onSourceMenu = { [weak self] view in
            self?.sourceMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        }
        root.onTargetMenu = { [weak self] view in
            self?.targetMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        }
        root.onMoved = { frame in Self.remember(frame) }

        // Follow the user to a full-screen call on its own Space.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak panel] _ in
                guard let panel, panel.isVisible else { return }
                panel.orderFrontRegardless()
            }
        return panel
    }

    // MARK: Position

    private static let topLeftKey = "livePanelTopLeft"

    private static func remember(_ frame: NSRect) {
        UserDefaults.standard.set([Double(frame.minX), Double(frame.maxY)], forKey: topLeftKey)
    }

    /// Where it was last left, if that display is still attached; otherwise the
    /// top-right corner, clear of the dictation pill lower down the right edge.
    private func initialFrame() -> NSRect {
        let size = NSSize(width: PanelView.width, height: root.preferredHeight)
        if let saved = UserDefaults.standard.array(forKey: Self.topLeftKey) as? [Double], saved.count == 2 {
            let topLeft = NSPoint(x: saved[0], y: saved[1])
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.insetBy(dx: -2, dy: -2).contains(topLeft) }) {
                let rect = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
                return HUD.confine(rect, near: NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY))
            }
        }
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(x: visible.maxX - size.width - 14, y: visible.maxY - size.height - 14,
                      width: size.width, height: size.height)
    }
}

// MARK: - Views

private final class PanelView: NSView {

    static let width: CGFloat = 460
    private static let gap: CGFloat = 8
    private static let transcriptHeight: CGFloat = 136
    private static let translationHeight: CGFloat = 166
    private static let soloHeight: CGFloat = 206

    var onClose: () -> Void = {}
    var onCopy: () -> Void = {}
    var onToggleLayout: () -> Void = {}
    var onSourceMenu: (NSView) -> Void = { _ in }
    var onTargetMenu: (NSView) -> Void = { _ in }
    var onMoved: (NSRect) -> Void = { _ in }

    var layoutMode: TranslatorPanel.Layout = .both {
        didSet {
            transcriptCard.isHidden = layoutMode == .translationOnly
            layoutButton.image = Self.symbol(layoutMode == .both ? "rectangle.bottomhalf.filled" : "rectangle.split.1x2")
            layoutButton.toolTip = layoutMode == .both ? "Show only the translation" : "Show what was said too"
            needsLayout = true
        }
    }

    var preferredHeight: CGFloat {
        layoutMode == .both
            ? Self.transcriptHeight + Self.gap + Self.translationHeight
            : Self.soloHeight
    }

    private let transcriptCard = CardView()
    private let translationCard = CardView()

    // Header — lives on whichever card is on top.
    private let dot = NSView()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let meter = WaveformView()
    private let sourceButton = HoverButton()
    private let layoutButton = HoverButton()
    private let copyButton = HoverButton()
    private let closeButton = HoverButton()

    private let heardLabel = NSTextField(labelWithString: "Heard")
    private let targetButton = HoverButton()
    private let originalText = CaptionView(fontSize: 13, weight: .regular, dimAlpha: 0.5)
    private let translatedText = CaptionView(fontSize: 17, weight: .medium, dimAlpha: 0.56)
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")
    private let noticeButton = HoverButton()
    private var noticeAction: (() -> Void)?

    private var dragOrigin: NSPoint?
    private var didDrag = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 300))
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        addSubview(transcriptCard)
        addSubview(translationCard)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        elapsedLabel.textColor = NSColor.white.withAlphaComponent(0.7)

        style(sourceButton, title: "System audio", menu: true)
        sourceButton.toolTip = "What to listen to"
        sourceButton.onClick = { [weak self] in
            guard let self else { return }
            self.onSourceMenu(self.sourceButton)
        }

        for (button, symbol, tip) in [
            (layoutButton, "rectangle.bottomhalf.filled", "Show only the translation"),
            (copyButton, "doc.on.doc", "Copy this session"),
            (closeButton, "xmark", "Stop live translation (Esc)"),
        ] {
            button.image = Self.symbol(symbol)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.toolTip = tip
            button.baseAlpha = 0.62
        }
        layoutButton.onClick = { [weak self] in self?.onToggleLayout() }
        copyButton.onClick = { [weak self] in self?.onCopy() }
        closeButton.onClick = { [weak self] in self?.onClose() }

        heardLabel.font = .systemFont(ofSize: 11, weight: .medium)
        heardLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        heardLabel.lineBreakMode = .byTruncatingTail

        style(targetButton, title: "English", menu: true, pill: true)
        targetButton.toolTip = "Translate into…"
        targetButton.onClick = { [weak self] in
            guard let self else { return }
            self.onTargetMenu(self.targetButton)
        }

        noticeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        noticeLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        noticeLabel.isSelectable = false
        noticeLabel.maximumNumberOfLines = 3

        style(noticeButton, title: "", menu: false)
        noticeButton.baseAlpha = 0.85
        noticeButton.isHidden = true
        noticeButton.onClick = { [weak self] in self?.noticeAction?() }

        transcriptCard.addSubview(heardLabel)
        transcriptCard.addSubview(originalText)
        [targetButton, translatedText, noticeLabel, noticeButton].forEach(translationCard.addSubview)
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
    }

    private func style(_ button: HoverButton, title: String, menu: Bool, pill: Bool = false) {
        button.isBordered = false
        button.pill = pill
        button.baseAlpha = pill ? 0.82 : 0.62
        button.font = pill ? .systemFont(ofSize: 11.5, weight: .semibold) : .systemFont(ofSize: 11, weight: .medium)
        button.setTitle(title, chevron: menu)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        let headerCard: CardView

        if layoutMode == .both {
            transcriptCard.frame = NSRect(x: 0, y: 0, width: w, height: Self.transcriptHeight)
            translationCard.frame = NSRect(x: 0, y: Self.transcriptHeight + Self.gap,
                                           width: w, height: Self.translationHeight)
            headerCard = transcriptCard
        } else {
            translationCard.frame = NSRect(x: 0, y: 0, width: w, height: Self.soloHeight)
            headerCard = translationCard
        }

        // Header row.
        for view in [dot, elapsedLabel, meter, sourceButton, layoutButton, copyButton, closeButton] as [NSView]
        where view.superview !== headerCard {
            headerCard.addSubview(view)
        }
        let rowY: CGFloat = 12
        let rowH: CGFloat = 18
        dot.frame = NSRect(x: 16, y: rowY + (rowH - 7) / 2, width: 7, height: 7)
        elapsedLabel.sizeToFit()
        elapsedLabel.frame = NSRect(x: dot.frame.maxX + 8, y: rowY + (rowH - elapsedLabel.frame.height) / 2,
                                    width: max(30, elapsedLabel.frame.width), height: elapsedLabel.frame.height)
        meter.frame = NSRect(x: elapsedLabel.frame.maxX + 8, y: rowY + 3, width: 72, height: 12)
        sourceButton.sizeToFit()
        sourceButton.frame = NSRect(x: meter.frame.maxX + 12, y: rowY, width: sourceButton.frame.width, height: rowH)

        var x = w - 12 - 22
        for button in [closeButton, copyButton, layoutButton] {
            button.frame = NSRect(x: x, y: rowY - 2, width: 22, height: 22)
            x -= 24
        }

        // Transcript card.
        let pad: CGFloat = 16
        heardLabel.frame = NSRect(x: pad, y: 40, width: w - pad * 2, height: 14)
        originalText.frame = NSRect(x: pad, y: 58, width: w - pad * 2, height: Self.transcriptHeight - 58 - 12)

        // Translation card.
        let top: CGFloat = layoutMode == .both ? 14 : 40
        targetButton.sizeToFit()
        targetButton.frame = NSRect(x: pad, y: top - 2, width: targetButton.frame.width + 20, height: 22)
        let textTop = top + 28
        translatedText.frame = NSRect(x: pad, y: textTop, width: w - pad * 2,
                                      height: translationCard.frame.height - textTop - 14)
        noticeLabel.frame = NSRect(x: pad, y: textTop + 2, width: w - pad * 2, height: 54)
        noticeButton.sizeToFit()
        noticeButton.frame = NSRect(x: pad - 2, y: textTop + 62, width: noticeButton.frame.width + 4, height: 18)
    }

    // MARK: Content

    func setActivity(_ activity: TranslatorPanel.Activity) {
        switch activity {
        case .listening:
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
        case .connecting:
            dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
            startPulse()
        case .stopped:
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
            stopPulse()
            meter.reset()
        }
    }

    func setElapsed(_ seconds: TimeInterval) {
        let whole = Int(seconds)
        let text = whole >= 3600
            ? String(format: "%d:%02d:%02d", whole / 3600, (whole / 60) % 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
        guard text != elapsedLabel.stringValue else { return }
        elapsedLabel.stringValue = text
        needsLayout = true
    }

    func setLevel(_ level: Float) { meter.push(level) }

    func setSource(_ title: String, menu: Bool) {
        sourceButton.setTitle(title, chevron: menu)
        needsLayout = true
    }

    func setHeard(_ languageName: String?) {
        heardLabel.stringValue = languageName.map { "Heard in \($0)" } ?? "Heard"
    }

    func setTarget(_ languageName: String) {
        targetButton.setTitle(languageName, chevron: true)
        needsLayout = true
    }

    func setNotice(_ message: String?, action: (title: String, run: () -> Void)?) {
        noticeLabel.stringValue = message ?? ""
        noticeLabel.isHidden = message == nil
        noticeAction = action?.run
        noticeButton.setTitle(action.map { "\($0.title) →" } ?? "", chevron: false)
        noticeButton.isHidden = action == nil
        translatedText.isHidden = message != nil
        needsLayout = true
    }

    func render(originals: [TranslatorPanel.Line], translations: [TranslatorPanel.Line]) {
        originalText.show(originals)
        translatedText.show(translations)
    }

    private func startPulse() {
        guard dot.layer?.animation(forKey: "pulse") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.2
        animation.duration = 0.72
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(animation, forKey: "pulse")
    }

    private func stopPulse() {
        dot.layer?.removeAnimation(forKey: "pulse")
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragOrigin = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - origin.x
        let dy = now.y - origin.y
        if !didDrag && (abs(dx) + abs(dy)) < 3 { return }
        didDrag = true
        var frame = window.frame
        frame.origin = NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy)
        window.setFrame(HUD.confine(frame, near: now), display: true)
        dragOrigin = now
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        if didDrag, let window { onMoved(window.frame) }
        didDrag = false
    }
}

/// One rounded glass card, the same recipe as the dictation panel.
private final class CardView: NSView {

    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let gloss = NSView()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 19
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(blur)

        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.90).cgColor
        tint.layer?.cornerRadius = 19
        tint.layer?.cornerCurve = .continuous
        tint.layer?.masksToBounds = true
        addSubview(tint)

        gloss.wantsLayer = true
        gloss.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        addSubview(gloss)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        gloss.frame = NSRect(x: 14, y: 1, width: bounds.width - 28, height: 1)
    }
}

/// Scrolling captions: newest line at the bottom and brightest, older lines
/// dimmer and fading out at the top edge. Follows the newest line unless you
/// have scrolled back to reread something.
private final class CaptionView: NSView {

    private let scroll = NSScrollView()
    private let text = PassiveTextView()
    private let fade = CAGradientLayer()
    private let font: NSFont
    private let dimAlpha: CGFloat
    /// Only the tail is drawn; the full session lives in the transcript model.
    private let maxLines = 60
    /// Keep the newest line in view. Off while you have scrolled back to
    /// reread; back on when you return to the bottom, or after a while.
    private var followsNewest = true
    private var lastUserScrollAt = Date.distantPast
    private static let resumeFollowingAfter: TimeInterval = 12

    override var isFlipped: Bool { true }

    init(fontSize: CGFloat, weight: NSFont.Weight, dimAlpha: CGFloat) {
        font = .systemFont(ofSize: fontSize, weight: weight)
        self.dimAlpha = dimAlpha
        super.init(frame: .zero)

        // No scroller: following the newest line would flash one on every
        // sentence. A trackpad still scrolls back to reread.
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .none
        scroll.wantsLayer = true
        addSubview(scroll)

        text.drawsBackground = false
        text.isEditable = false
        text.isSelectable = false
        text.isRichText = true
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        scroll.documentView = text

        // Inside a flipped view the layer's unit space is flipped too: y 0 is
        // the top edge, where older lines fade out.
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        fade.locations = [0, 0.28, 1]
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        scroll.layer?.mask = fade

        NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
                                               object: scroll, queue: .main) { [weak self] _ in
            self?.lastUserScrollAt = Date()
        }
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
                                               object: scroll, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lastUserScrollAt = Date()
            self.followsNewest = self.isAtBottom
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.frame.size.width = scroll.contentSize.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = scroll.bounds
        CATransaction.commit()
        if followsNewest { scrollToBottom() }
    }

    func show(_ lines: [TranslatorPanel.Line]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(2, font.pointSize * 0.2)
        paragraph.paragraphSpacing = font.pointSize * 0.45

        let out = NSMutableAttributedString()
        for (index, line) in lines.suffix(maxLines).enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            let alpha: CGFloat = line.isCurrent ? (line.isDraft ? 0.78 : 0.96) : dimAlpha
            out.append(NSAttributedString(string: line.text, attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                .paragraphStyle: paragraph,
            ]))
        }
        text.textStorage?.setAttributedString(out)
        if !followsNewest, Date().timeIntervalSince(lastUserScrollAt) > Self.resumeFollowingAfter {
            followsNewest = true
        }
        if followsNewest { scrollToBottom() }
        text.needsDisplay = true
    }

    private var isAtBottom: Bool {
        scroll.contentView.bounds.maxY >= text.frame.height - 8
    }

    private func scrollToBottom() {
        if let layoutManager = text.layoutManager, let container = text.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        text.sizeToFit()
        let y = max(0, text.frame.height - scroll.contentSize.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// Display-only text. Sits flush with the bottom while it is shorter than the
/// view, the way captions do, and lets clicks through so the panel can be
/// dragged by its text.
private final class PassiveTextView: NSTextView {

    override var textContainerOrigin: NSPoint {
        guard let layoutManager, let textContainer else { return super.textContainerOrigin }
        let used = layoutManager.usedRect(for: textContainer).height
        return NSPoint(x: 0, y: max(0, bounds.height - used))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A borderless control that brightens under the pointer.
private final class HoverButton: NSButton {

    var onClick: () -> Void = {}
    var baseAlpha: CGFloat = 0.5 { didSet { refresh() } }
    /// A soft capsule behind the title, so a picker reads as something to press.
    var pill = false {
        didSet {
            wantsLayer = pill
            layer?.cornerCurve = .continuous
            refresh()
        }
    }
    private var hovering = false
    private var plainTitle = ""
    private var chevron = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(clicked)
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onClick() }

    func setTitle(_ title: String, chevron: Bool) {
        plainTitle = title
        self.chevron = chevron
        refresh()
    }

    private func refresh() {
        let color = NSColor.white.withAlphaComponent(hovering ? min(1, baseAlpha + 0.4) : baseAlpha)
        contentTintColor = color
        if pill {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(hovering ? 0.17 : 0.09).cgColor
        }
        guard !plainTitle.isEmpty else {
            attributedTitle = NSAttributedString(string: "")
            return
        }
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        attributedTitle = NSAttributedString(string: plainTitle + (chevron ? "  ▾" : ""), attributes: [
            .font: font ?? .systemFont(ofSize: 11),
            .foregroundColor: color,
            .paragraphStyle: centred,
        ])
    }

    override func layout() {
        super.layout()
        if pill { layer?.cornerRadius = bounds.height / 2 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refresh()
    }
}
