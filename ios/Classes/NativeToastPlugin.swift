import Flutter
import UIKit

public class NativeToastPlugin: NSObject, FlutterPlugin, UIGestureRecognizerDelegate {

    private var activeToasts: [ToastEntry] = []
    private let toastAnimationOvershoot: CGFloat = 12
    private let toastDismissThreshold: CGFloat = 56
    private let toastAnimationDuration: TimeInterval = 0.35

    struct ToastEntry {
        let window: UIWindow
        let containerView: UIView
        let position: String
        let dismissDirection: String
        var dismissWorkItem: DispatchWorkItem?
        var timerFireDate: Date?       // nil when paused or length == "never"
        var remainingDuration: TimeInterval  // updated on pause
    }

    // ─── Registration ─────────────────────────────────────────────────────────

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.yourapp/native_toast",
            binaryMessenger: registrar.messenger()
        )
        let instance = NativeToastPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // ─── MethodChannel handler ────────────────────────────────────────────────

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "showToast" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected a dictionary", details: nil))
            return
        }

        let type            = args["type"]            as? String ?? "success"
        let message         = args["message"]         as? String ?? ""
        let position        = args["position"]        as? String ?? "top"
        let length          = args["length"]          as? String ?? "short"
        let duration        = durationFor(durationMs: args["durationMs"], length: length)
        let color           = colorFor(value: args["color"])
        let icon            = args["icon"]            as? String ?? type
        let iconColor       = colorFor(value: args["iconColor"]) ?? .white
        let dismissDirection = args["dismissDirection"] as? String
            ?? (position == "top" ? "up" : "down")

        DispatchQueue.main.async {
            self.showToast(type: type, message: message, position: position,
                           duration: duration, color: color, icon: icon, iconColor: iconColor,
                           dismissDirection: dismissDirection)
        }
        result(nil)
    }

    // ─── Toast presentation ───────────────────────────────────────────────────

    private func showToast(
        type: String, message: String, position: String,
        duration: TimeInterval, color: UIColor?, icon: String, iconColor: UIColor,
        dismissDirection: String
    ) {
        guard let scene = activeWindowScene() else { return }

        let screenBounds = scene.coordinateSpace.bounds
        let maxWidth = screenBounds.width - 32

        let containerView = buildToastView(type: type, message: message, color: color,
                                           icon: icon, iconColor: iconColor,
                                           maxWidth: maxWidth)
        containerView.layoutIfNeeded()
        let fittingSize = containerView.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let toastWidth = maxWidth
        let toastHeight = max(fittingSize.height, 40)

        let stackedOffset = stackOffset(for: position)
        let safeInsets = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
        let edgeMargin: CGFloat = 64
        let topMargin = max(edgeMargin, safeInsets.top + 16)
        let bottomMargin = max(edgeMargin, safeInsets.bottom + 16)
        let xPos = (screenBounds.width - toastWidth) / 2
        let yPos: CGFloat = position == "top"
            ? topMargin + stackedOffset
            : screenBounds.height - bottomMargin - toastHeight - stackedOffset

        containerView.frame = CGRect(x: xPos, y: yPos, width: toastWidth, height: toastHeight)

        let toastWindow = PassthroughWindow(windowScene: scene)
        toastWindow.frame = screenBounds
        toastWindow.windowLevel = UIWindow.Level.alert + 1
        toastWindow.backgroundColor = .clear
        toastWindow.isUserInteractionEnabled = true

        let rootVC = PassthroughViewController()
        rootVC.view.frame = screenBounds
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = true
        toastWindow.rootViewController = rootVC
        toastWindow.isHidden = false
        rootVC.view.addSubview(containerView)

        let entry = ToastEntry(
            window: toastWindow,
            containerView: containerView,
            position: position,
            dismissDirection: dismissDirection,
            dismissWorkItem: nil,
            timerFireDate: nil,
            remainingDuration: max(duration, 0)
        )
        activeToasts.append(entry)
        rebuildOffsets()

        animateIn(view: containerView, position: position)
        attachGestures(to: containerView, entry: entry)

        if duration > 0 {
            scheduleTimer(forWindow: toastWindow, duration: duration)
        }
    }

    // ─── Timer scheduling / pause / resume ───────────────────────────────────

    private func scheduleTimer(forWindow window: UIWindow, duration: TimeInterval) {
        guard let idx = activeToasts.firstIndex(where: { $0.window === window }) else { return }

        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self = self, let win = window,
                  let current = self.activeToasts.first(where: { $0.window === win }) else { return }
            self.dismissToast(entry: current)
        }
        activeToasts[idx].dismissWorkItem = workItem
        activeToasts[idx].timerFireDate   = Date().addingTimeInterval(duration)
        activeToasts[idx].remainingDuration = duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func pauseTimer(forWindow window: UIWindow) {
        guard let idx = activeToasts.firstIndex(where: { $0.window === window }) else { return }
        guard let fireDate = activeToasts[idx].timerFireDate else { return } // already paused or "never"

        activeToasts[idx].dismissWorkItem?.cancel()
        activeToasts[idx].dismissWorkItem = nil
        let remaining = max(fireDate.timeIntervalSince(Date()), 0.2)
        activeToasts[idx].remainingDuration = remaining
        activeToasts[idx].timerFireDate = nil
    }

    private func resumeTimer(forWindow window: UIWindow) {
        guard let idx = activeToasts.firstIndex(where: { $0.window === window }) else { return }
        guard activeToasts[idx].timerFireDate == nil else { return } // already running
        let remaining = activeToasts[idx].remainingDuration
        guard remaining > 0 else { return } // "never" toast — don't reschedule
        scheduleTimer(forWindow: window, duration: remaining)
    }

    // ─── View builder ─────────────────────────────────────────────────────────

    private func buildToastView(type: String, message: String, color: UIColor?,
                                icon: String, iconColor: UIColor,
                                maxWidth: CGFloat) -> UIView {
        let bgColor: UIColor = color ?? {
            switch type {
            case "success": return UIColor(red: 0.11, green: 0.54, blue: 0.09, alpha: 1)
            case "error":   return UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1)
            default:        return UIColor(red: 0.80, green: 0.56, blue: 0.07, alpha: 1)
            }
        }()
        let container = UIView()
        container.backgroundColor = bgColor
        container.layer.cornerRadius = 16
        container.layer.masksToBounds = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.22
        container.layer.shadowRadius = 6
        container.layer.shadowOffset = CGSize(width: 0, height: 2)

        // Plain text — no custom line-height paragraph style. A forced line box
        // taller than the glyph pushes the glyph below the line box centre, so
        // .center alignment in the stack ends up visually mismatched with the
        // icon. Natural font metrics keep the glyph centre on the same axis
        // as the icon centre.
        let msgLabel = UILabel()
        msgLabel.text = message
        msgLabel.textColor = .white
        msgLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        msgLabel.numberOfLines = 0
        msgLabel.translatesAutoresizingMaskIntoConstraints = false
        msgLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // Golden ratio (φ ≈ 1.618), base unit = 12pt:
        //   verticalPadding(12) = base   |  horizontalPadding(20) = base × φ
        //   iconSize(20) = horizontal padding (edge unity)
        //   iconGap(12)  = vertical padding   (edge unity)
        //   icon/gap = horizontal/vertical = 20/12 ≈ φ
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 20,
            bottom: 12,
            trailing: 20
        )
        container.addSubview(stackView)

        var constraints: [NSLayoutConstraint] = [
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        if let iconView = makeIconView(icon: icon, color: iconColor) {
            stackView.addArrangedSubview(iconView)
            constraints.append(contentsOf: [
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20),
            ])
        }
        stackView.addArrangedSubview(msgLabel)

        NSLayoutConstraint.activate(constraints)
        container.widthAnchor.constraint(equalToConstant: maxWidth).isActive = true
        return container
    }

    private func makeIconView(icon: String, color: UIColor) -> UIView? {
        guard icon != "none" else { return nil }
        let iconView = ToastIconView(type: icon, color: color)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        return iconView
    }

    // ─── Enter / exit animations ─────────────────────────────────────────────

    private func animateIn(view: UIView, position: String) {
        let offset = animationOffset(for: view, position: position)
        view.transform = CGAffineTransform(translationX: 0, y: offset)
        view.alpha = 0
        UIView.animate(
            withDuration: toastAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                view.transform = .identity
                view.alpha = 1
            }
        )
    }

    private func animateOut(view: UIView, position: String, completion: @escaping () -> Void) {
        // Additive: animate from the current transform (possibly mid-drag)
        // and add the slide delta on top, so the visible slide distance stays
        // consistent regardless of how far the user dragged. Without this, a
        // dragged-then-released toast only travels the tiny remaining gap and
        // looks like a stutter instead of a smooth continuation off-screen.
        let offset = animationOffset(for: view, position: position)
        let targetY = view.transform.ty + offset
        UIView.animate(
            withDuration: toastAnimationDuration,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: {
                view.transform = CGAffineTransform(translationX: 0, y: targetY)
                view.alpha = 0
            },
            completion: { _ in completion() }
        )
    }

    private func animationOffset(for view: UIView, position: String) -> CGFloat {
        guard let superview = view.superview else {
            return position == "top" ? -view.bounds.height : view.bounds.height
        }

        if position == "top" {
            return -(view.frame.maxY + toastAnimationOvershoot)
        }
        return superview.bounds.height - view.frame.minY + toastAnimationOvershoot
    }

    // ─── Dismiss ─────────────────────────────────────────────────────────────

    private func dismissToast(entry: ToastEntry) {
        guard activeToasts.contains(where: { $0.window === entry.window }) else { return }
        entry.dismissWorkItem?.cancel()
        animateOut(view: entry.containerView, position: entry.position) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                entry.window.isHidden = true
                self.activeToasts.removeAll { $0.window === entry.window }
                self.rebuildOffsets()
            }
        }
    }

    // ─── Stacking ─────────────────────────────────────────────────────────────

    private func stackOffset(for position: String) -> CGFloat {
        if position == "bottom" {
            return 0
        }
        return activeToasts.filter { $0.position == position }
            .reduce(0) { $0 + $1.containerView.frame.height + 8 }
    }

    private func rebuildOffsets() {
        guard let scene = activeWindowScene() else { return }
        let screenBounds = scene.coordinateSpace.bounds
        let safeInsets = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
        let edgeMargin: CGFloat = 64
        let topMargin = max(edgeMargin, safeInsets.top + 16)
        let bottomMargin = max(edgeMargin, safeInsets.bottom + 16)

        var topOffset = topMargin
        for e in activeToasts.filter({ $0.position == "top" }) {
            reposition(e.containerView, toOriginY: topOffset)
            topOffset += e.containerView.bounds.height + 8
        }

        var bottomOffset = bottomMargin
        for e in activeToasts.filter({ $0.position == "bottom" }).reversed() {
            let targetY = screenBounds.height - bottomOffset - e.containerView.bounds.height
            reposition(e.containerView, toOriginY: targetY)
            bottomOffset += e.containerView.bounds.height + 8
        }
    }

    // Animates the view's frame.origin.y so existing toasts smoothly slide into
    // place when neighbours are added or removed — without this the bottom-stack
    // would teleport upward whenever a new bottom toast arrives.
    private func reposition(_ view: UIView, toOriginY targetY: CGFloat) {
        if abs(view.frame.origin.y - targetY) < 0.5 { return }
        var newFrame = view.frame
        newFrame.origin.y = targetY
        UIView.animate(
            withDuration: toastAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            view.frame = newFrame
        }
    }

    // ─── Gesture attachment ───────────────────────────────────────────────────

    private func attachGestures(to view: UIView, entry: ToastEntry) {
        let toastWindow = entry.window

        // Hold: pause timer on touch-down, resume on lift.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0
        hold.cancelsTouchesInView = false
        hold.delegate = self
        view.addGestureRecognizer(hold)
        objc_setAssociatedObject(hold, &AssociatedKeys.entry, toastWindow, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Pan: visual drag + threshold dismiss or spring bounce-back.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        objc_setAssociatedObject(pan, &AssociatedKeys.entry,     toastWindow,                      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(pan, &AssociatedKeys.direction, entry.dismissDirection as NSString, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    }

    // Allow hold and pan to run simultaneously so hold can pause the timer
    // while a swipe is in progress.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    // ─── Gesture handlers ─────────────────────────────────────────────────────

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        guard let win = objc_getAssociatedObject(recognizer, &AssociatedKeys.entry) as? UIWindow
        else { return }
        switch recognizer.state {
        case .began:
            pauseTimer(forWindow: win)
        case .ended, .cancelled, .failed:
            resumeTimer(forWindow: win)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let win = objc_getAssociatedObject(recognizer, &AssociatedKeys.entry) as? UIWindow,
              let entry = activeToasts.first(where: { $0.window === win })
        else { return }
        let direction = objc_getAssociatedObject(recognizer, &AssociatedKeys.direction) as? String ?? "up"
        let superview = entry.containerView.superview

        switch recognizer.state {
        case .changed:
            let dy = recognizer.translation(in: superview).y
            // Clamp to dismiss direction — resists dragging the wrong way.
            let clamped: CGFloat = direction == "up" ? min(dy, 0) : max(dy, 0)
            entry.containerView.transform = CGAffineTransform(translationX: 0, y: clamped)

        case .ended:
            let translation = recognizer.translation(in: superview).y
            let shouldDismiss: Bool = direction == "up"
                ? translation < -toastDismissThreshold
                : translation >  toastDismissThreshold

            if shouldDismiss {
                dismissToast(entry: entry)
            } else {
                UIView.animate(
                    withDuration: 0.4, delay: 0,
                    usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8,
                    options: [.curveEaseOut]
                ) { entry.containerView.transform = .identity }
            }

        case .cancelled:
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                entry.containerView.transform = .identity
            }

        default:
            break
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private func durationFor(durationMs: Any?, length: String) -> TimeInterval {
        if let milliseconds = durationMs as? NSNumber {
            return milliseconds.doubleValue / 1000
        }

        switch length {
        case "short":  return 2
        case "medium": return 4
        case "long":   return 6
        case "ages":   return 10
        case "never":  return -1
        default:       return 2
        }
    }

    private func colorFor(value: Any?) -> UIColor? {
        guard let number = value as? NSNumber else { return nil }
        let argb = number.uint32Value
        return UIColor(
            red: CGFloat((argb >> 16) & 0xff) / 255,
            green: CGFloat((argb >> 8) & 0xff) / 255,
            blue: CGFloat(argb & 0xff) / 255,
            alpha: CGFloat((argb >> 24) & 0xff) / 255
        )
    }

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
    }
}

// ─── Toast icon ───────────────────────────────────────────────────────────────

private class ToastIconView: UIView {
    private let type: String
    private let color: UIColor

    init(type: String, color: UIColor) {
        self.type = type
        self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let strokeWidth: CGFloat = 2.4
        let inset = strokeWidth / 2
        let circleRect = rect.insetBy(dx: inset, dy: inset)

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.strokeEllipse(in: circleRect)

        switch type {
        case "success":
            drawLine(from: CGPoint(x: rect.width * 0.28, y: rect.height * 0.52),
                     to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.68))
            drawLine(from: CGPoint(x: rect.width * 0.43, y: rect.height * 0.68),
                     to: CGPoint(x: rect.width * 0.73, y: rect.height * 0.35))

        case "error":
            drawLine(from: CGPoint(x: rect.width * 0.35, y: rect.height * 0.35),
                     to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.65))
            drawLine(from: CGPoint(x: rect.width * 0.65, y: rect.height * 0.35),
                     to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.65))

        default:
            drawLine(from: CGPoint(x: rect.midX, y: rect.height * 0.42),
                     to: CGPoint(x: rect.midX, y: rect.height * 0.70))
            context.fillEllipse(
                in: CGRect(
                    x: rect.midX - strokeWidth / 2,
                    y: rect.height * 0.30 - strokeWidth / 2,
                    width: strokeWidth,
                    height: strokeWidth
                )
            )
        }
    }

    private func drawLine(from start: CGPoint, to end: CGPoint) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }
}

// ─── Associated object keys ───────────────────────────────────────────────────

private enum AssociatedKeys {
    static var entry     = "toastEntry"
    static var direction = "toastDirection"
}

// ─── Passthrough window root ──────────────────────────────────────────────────

private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === rootViewController?.view {
            return nil
        }
        return hit
    }
}

private class PassthroughViewController: UIViewController {
    override func loadView() { view = PassthroughView() }
}

private class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
