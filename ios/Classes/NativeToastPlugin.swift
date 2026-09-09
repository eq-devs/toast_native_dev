import Flutter
import UIKit

public class NativeToastPlugin: NSObject, FlutterPlugin, UIGestureRecognizerDelegate {

    private var activeToasts: [ToastEntry] = []
    // Single shared window hosting every toast — UIWindow is the most expensive
    // UIKit object to create, so we make one lazily and keep it for the app's
    // lifetime instead of one per toast.
    private var overlayWindow: PassthroughWindow?
    private let toastAnimationOvershoot: CGFloat = 12
    private let toastDismissThreshold: CGFloat = 56
    private let toastAnimationDuration: TimeInterval = 0.35

    struct ToastEntry {
        let containerView: UIView
        let position: String
        let dismissDirection: String
        var dismissWorkItem: DispatchWorkItem?
        var timerFireUptime: TimeInterval?   // nil when paused or length == "never"
        var remainingDuration: TimeInterval  // updated on pause
    }

    // ─── Registration ─────────────────────────────────────────────────────────

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "toast_native_dev/channel",
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

        let payload = NativeToastPayload.parse(args)
        if !payload.shouldShow {
            result(nil)
            return
        }

        // MethodChannel callbacks already arrive on the main thread.
        showToast(
            type: payload.type,
            title: payload.title,
            subtitle: payload.subtitle,
            position: payload.position,
            duration: payload.duration,
            color: payload.backgroundColor,
            icon: payload.icon,
            iconColor: payload.resolvedIconColor,
            dismissDirection: payload.dismissDirection
        )
        result(nil)
    }

    // ─── Toast presentation ───────────────────────────────────────────────────

    private func showToast(
        type: String, title: String, subtitle: String, position: String,
        duration: TimeInterval, color: UIColor?, icon: String, iconColor: UIColor,
        dismissDirection: String
    ) {
        guard let toastWindow = presentationWindow(),
              let scene = toastWindow.windowScene,
              let rootView = toastWindow.rootViewController?.view else { return }

        let screenBounds = scene.coordinateSpace.bounds
        let maxWidth = screenBounds.width - 28

        let containerView = buildToastView(type: type, title: title, subtitle: subtitle,
                                           color: color, icon: icon, iconColor: iconColor,
                                           maxWidth: maxWidth)
        let fittingSize = containerView.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let toastWidth = maxWidth
        let toastHeight = max(fittingSize.height, 40)

        let stackedOffset = stackOffset(for: position)
        let safeInsets = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
        let edgeMargin: CGFloat = 14
        let topMargin = max(edgeMargin, safeInsets.top + 14)
        let bottomMargin = max(edgeMargin, safeInsets.bottom + 14)
        let xPos = (screenBounds.width - toastWidth) / 2
        let yPos: CGFloat = position == "top"
            ? topMargin + stackedOffset
            : screenBounds.height - bottomMargin - toastHeight - stackedOffset

        containerView.frame = CGRect(x: xPos, y: yPos, width: toastWidth, height: toastHeight)
        rootView.addSubview(containerView)

        let entry = ToastEntry(
            containerView: containerView,
            position: position,
            dismissDirection: dismissDirection,
            dismissWorkItem: nil,
            timerFireUptime: nil,
            remainingDuration: max(duration, 0)
        )
        activeToasts.append(entry)
        rebuildOffsets()

        animateIn(view: containerView, position: position)
        attachGestures(to: containerView)

        if duration > 0 {
            scheduleTimer(forView: containerView, duration: duration)
        }
    }

    // Returns the shared overlay window, creating it on first use or after its
    // scene has been disconnected (e.g. iPad window closed).
    private func presentationWindow() -> UIWindow? {
        if let window = overlayWindow, window.windowScene != nil {
            window.isHidden = false
            return window
        }

        // Scene gone — any surviving entries reference views in a dead window.
        for entry in activeToasts { entry.dismissWorkItem?.cancel() }
        activeToasts.removeAll()

        guard let scene = activeWindowScene() else { return nil }
        let window = PassthroughWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = true

        let rootVC = PassthroughViewController()
        rootVC.view.frame = window.frame
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = true
        window.rootViewController = rootVC
        window.isHidden = false
        overlayWindow = window
        return window
    }

    // ─── Timer scheduling / pause / resume ───────────────────────────────────

    private func scheduleTimer(forView view: UIView, duration: TimeInterval) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }) else { return }

        let workItem = DispatchWorkItem { [weak self, weak view] in
            guard let self = self, let view = view,
                  let current = self.activeToasts.first(where: { $0.containerView === view }) else { return }
            self.dismissToast(entry: current)
        }
        activeToasts[idx].dismissWorkItem = workItem
        // Monotonic clock — wall time (Date) can jump under NTP sync or manual
        // clock changes and corrupt the remaining duration on pause.
        activeToasts[idx].timerFireUptime = ProcessInfo.processInfo.systemUptime + duration
        activeToasts[idx].remainingDuration = duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func pauseTimer(forView view: UIView) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }) else { return }
        guard let fireUptime = activeToasts[idx].timerFireUptime else { return } // already paused or "never"

        activeToasts[idx].dismissWorkItem?.cancel()
        activeToasts[idx].dismissWorkItem = nil
        let remaining = max(fireUptime - ProcessInfo.processInfo.systemUptime, 0.2)
        activeToasts[idx].remainingDuration = remaining
        activeToasts[idx].timerFireUptime = nil
    }

    private func resumeTimer(forView view: UIView) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }) else { return }
        guard activeToasts[idx].timerFireUptime == nil else { return } // already running
        let remaining = activeToasts[idx].remainingDuration
        guard remaining > 0 else { return } // "never" toast — don't reschedule
        scheduleTimer(forView: view, duration: remaining)
    }

    // ─── View builder ─────────────────────────────────────────────────────────

    private func buildToastView(type: String, title: String, subtitle: String,
                                color: UIColor?, icon: String, iconColor: UIColor,
                                maxWidth: CGFloat) -> UIView {
        let bgColor: UIColor = color ?? {
            switch type {
            case "success": return UIColor(red: 24/255, green: 169/255, blue: 87/255, alpha: 1)
            case "error":   return UIColor(red: 251/255, green: 44/255, blue: 54/255, alpha: 1)
            case "info":    return UIColor(red: 150/255, green: 150/255, blue: 150/255, alpha: 1)
            default:        return UIColor(red: 248/255, green: 182/255, blue: 50/255, alpha: 1)
            }
        }()
        let container = UIView()
        container.backgroundColor = bgColor
        container.layer.cornerRadius = 16
        container.layer.masksToBounds = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.10
        container.layer.shadowRadius = 4
        container.layer.shadowOffset = CGSize(width: 0, height: 1)

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 0

        if !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.textColor = .white
            titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            titleLabel.numberOfLines = 0
            titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            textStack.addArrangedSubview(titleLabel)
        }
        if !subtitle.isEmpty {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.textColor = .white
            subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
            subtitleLabel.numberOfLines = 0
            textStack.addArrangedSubview(subtitleLabel)
        }

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 16,
            bottom: 12,
            trailing: 16
        )
        container.addSubview(stackView)

        var constraints: [NSLayoutConstraint] = [
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        if let iconView = makeIconView(icon: icon, iconColor: iconColor, glyphColor: bgColor) {
            stackView.addArrangedSubview(iconView)
            constraints.append(contentsOf: [
                iconView.widthAnchor.constraint(equalToConstant: 24),
                iconView.heightAnchor.constraint(equalToConstant: 24),
            ])
        }
        stackView.addArrangedSubview(textStack)

        NSLayoutConstraint.activate(constraints)
        container.widthAnchor.constraint(equalToConstant: maxWidth).isActive = true
        return container
    }

    private func makeIconView(icon: String, iconColor: UIColor, glyphColor: UIColor) -> UIView? {
        guard icon != "none" else { return nil }
        let iconView = ToastIconView(type: icon, iconColor: iconColor, glyphColor: glyphColor)
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
        guard activeToasts.contains(where: { $0.containerView === entry.containerView }) else { return }
        entry.dismissWorkItem?.cancel()
        // Lock out further touches so an active pan/hold can't keep writing
        // .transform mid-animation and fight the slide-off.
        entry.containerView.isUserInteractionEnabled = false
        animateOut(view: entry.containerView, position: entry.position) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                entry.containerView.removeFromSuperview()
                self.activeToasts.removeAll { $0.containerView === entry.containerView }
                self.rebuildOffsets()
                if self.activeToasts.isEmpty {
                    self.overlayWindow?.isHidden = true
                }
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
        guard let scene = overlayWindow?.windowScene else { return }
        let screenBounds = scene.coordinateSpace.bounds
        let safeInsets = scene.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
        let edgeMargin: CGFloat = 14
        let topMargin = max(edgeMargin, safeInsets.top + 14)
        let bottomMargin = max(edgeMargin, safeInsets.bottom + 14)

        // Partition once instead of filtering twice.
        var topToasts: [ToastEntry] = []
        var bottomToasts: [ToastEntry] = []
        topToasts.reserveCapacity(activeToasts.count)
        bottomToasts.reserveCapacity(activeToasts.count)
        for entry in activeToasts {
            if entry.position == "top" {
                topToasts.append(entry)
            } else {
                bottomToasts.append(entry)
            }
        }

        var topOffset = topMargin
        for e in topToasts {
            reposition(e.containerView, toOriginY: topOffset)
            topOffset += e.containerView.bounds.height + 8
        }

        var bottomOffset = bottomMargin
        for e in bottomToasts.reversed() {
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

    // Recognizers are attached to the toast's containerView, so handlers
    // recover the entry via recognizer.view — no associated objects needed.
    private func attachGestures(to view: UIView) {
        // Hold: pause timer on touch-down, resume on lift.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0
        hold.cancelsTouchesInView = false
        hold.delegate = self
        view.addGestureRecognizer(hold)

        // Pan: visual drag + threshold dismiss or spring bounce-back.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    // Allow hold and pan to run simultaneously so hold can pause the timer
    // while a swipe is in progress.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }

    // ─── Gesture handlers ─────────────────────────────────────────────────────

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        guard let view = recognizer.view else { return }
        switch recognizer.state {
        case .began:
            pauseTimer(forView: view)
        case .ended, .cancelled, .failed:
            resumeTimer(forView: view)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view,
              let entry = activeToasts.first(where: { $0.containerView === view })
        else { return }
        let direction = entry.dismissDirection
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

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
    }
}

// ─── Toast icon ───────────────────────────────────────────────────────────────

private class ToastIconView: UIView {
    private let type: String
    private let iconColor: UIColor
    private let glyphColor: UIColor

    init(type: String, iconColor: UIColor, glyphColor: UIColor) {
        self.type = type
        self.iconColor = iconColor
        self.glyphColor = glyphColor
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let s = min(rect.width, rect.height) / 24
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: s, y: s)

        if type == "info" {
            context.setFillColor(iconColor.cgColor)
            context.addPath(ToastIconView.wifiFillPath.cgPath)
            context.fillPath()
            context.setStrokeColor(iconColor.cgColor)
            context.setLineWidth(1.3301)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 4.23901, y: 4.16736))
            context.addLine(to: CGPoint(x: 18.4817, y: 18.4104))
            context.strokePath()
            context.addArc(center: CGPoint(x: 12.041, y: 18.8081), radius: 1.27515,
                           startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.fillPath()
            context.restoreGState()
            return
        }

        context.setFillColor(iconColor.cgColor)
        context.setStrokeColor(iconColor.cgColor)
        context.setLineWidth(1.5)
        context.addArc(center: CGPoint(x: 12, y: 12), radius: 10, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.drawPath(using: .fillStroke)

        context.setStrokeColor(glyphColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch type {
        case "success":
            context.move(to: CGPoint(x: 8.5, y: 12.5))
            context.addLine(to: CGPoint(x: 10.5, y: 14.5))
            context.addLine(to: CGPoint(x: 15.5, y: 9.5))
            context.strokePath()
        case "error":
            context.move(to: CGPoint(x: 14.5, y: 9.5))
            context.addLine(to: CGPoint(x: 9.5, y: 14.5))
            context.strokePath()
            context.move(to: CGPoint(x: 9.5, y: 9.5))
            context.addLine(to: CGPoint(x: 14.5, y: 14.5))
            context.strokePath()
        default:
            context.move(to: CGPoint(x: 12, y: 17))
            context.addLine(to: CGPoint(x: 12, y: 11))
            context.strokePath()
            context.setFillColor(iconColor.cgColor)
            context.setStrokeColor(glyphColor.cgColor)
            context.setLineWidth(1)
            context.addArc(center: CGPoint(x: 12, y: 8), radius: 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.drawPath(using: .fillStroke)
        }

        context.restoreGState()
    }

    private static let wifiFillPath: UIBezierPath = {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 8.60791, y: 15.5467))
        path.addCurve(to: CGPoint(x: 12.438, y: 14.0594), controlPoint1: CGPoint(x: 9.65063, y: 14.4213), controlPoint2: CGPoint(x: 11.0666, y: 13.9257))
        path.addLine(to: CGPoint(x: 15.3364, y: 16.9579))
        path.addCurve(to: CGPoint(x: 13.9282, y: 16.9032), controlPoint1: CGPoint(x: 14.9322, y: 17.3308), controlPoint2: CGPoint(x: 14.3022, y: 17.3068))
        path.addCurve(to: CGPoint(x: 10.0718, y: 16.9032), controlPoint1: CGPoint(x: 12.8538, y: 15.7435), controlPoint2: CGPoint(x: 11.1462, y: 15.7435))
        path.addCurve(to: CGPoint(x: 8.66162, y: 16.9569), controlPoint1: CGPoint(x: 9.69733, y: 17.3072), controlPoint2: CGPoint(x: 9.06574, y: 17.3313))
        path.addCurve(to: CGPoint(x: 8.60791, y: 15.5467), controlPoint1: CGPoint(x: 8.25755, y: 16.5824), controlPoint2: CGPoint(x: 8.2335, y: 15.9508))
        path.close()
        path.move(to: CGPoint(x: 10.5337, y: 12.1551))
        path.addCurve(to: CGPoint(x: 7.41162, y: 14.0311), controlPoint1: CGPoint(x: 9.39159, y: 12.4416), controlPoint2: CGPoint(x: 8.30586, y: 13.0659))
        path.addCurve(to: CGPoint(x: 6.00147, y: 14.0848), controlPoint1: CGPoint(x: 7.03719, y: 14.4352), controlPoint2: CGPoint(x: 6.40562, y: 14.4592))
        path.addCurve(to: CGPoint(x: 5.94776, y: 12.6756), controlPoint1: CGPoint(x: 5.59764, y: 13.7104), controlPoint2: CGPoint(x: 5.57366, y: 13.0797))
        path.addCurve(to: CGPoint(x: 8.95654, y: 10.578), controlPoint1: CGPoint(x: 6.82913, y: 11.7243), controlPoint2: CGPoint(x: 7.85866, y: 11.0262))
        path.addLine(to: CGPoint(x: 10.5337, y: 12.1551))
        path.close()
        path.move(to: CGPoint(x: 11.7476, y: 9.98325))
        path.addCurve(to: CGPoint(x: 18.0522, y: 12.6756), controlPoint1: CGPoint(x: 14.0238, y: 9.91151), controlPoint2: CGPoint(x: 16.3217, y: 10.8077))
        path.addCurve(to: CGPoint(x: 17.9985, y: 14.0848), controlPoint1: CGPoint(x: 18.4265, y: 13.0797), controlPoint2: CGPoint(x: 18.4025, y: 13.7104))
        path.addCurve(to: CGPoint(x: 16.5884, y: 14.0311), controlPoint1: CGPoint(x: 17.5944, y: 14.4592), controlPoint2: CGPoint(x: 16.9628, y: 14.4352))
        path.addCurve(to: CGPoint(x: 14.1235, y: 12.3582), controlPoint1: CGPoint(x: 15.8675, y: 13.253), controlPoint2: CGPoint(x: 15.0225, y: 12.6952))
        path.addLine(to: CGPoint(x: 11.7476, y: 9.98325))
        path.close()
        path.move(to: CGPoint(x: 7.4458, y: 9.06723))
        path.addCurve(to: CGPoint(x: 4.75147, y: 11.16), controlPoint1: CGPoint(x: 6.47472, y: 9.5887), controlPoint2: CGPoint(x: 5.56231, y: 10.2849))
        path.addCurve(to: CGPoint(x: 3.34131, y: 11.2137), controlPoint1: CGPoint(x: 4.37703, y: 11.5642), controlPoint2: CGPoint(x: 3.74546, y: 11.5882))
        path.addCurve(to: CGPoint(x: 3.2876, y: 9.80454), controlPoint1: CGPoint(x: 2.93746, y: 10.8393), controlPoint2: CGPoint(x: 2.91343, y: 10.2086))
        path.addCurve(to: CGPoint(x: 5.98096, y: 7.60239), controlPoint1: CGPoint(x: 4.10747, y: 8.9196), controlPoint2: CGPoint(x: 5.01521, y: 8.18517))
        path.addLine(to: CGPoint(x: 7.4458, y: 9.06723))
        path.close()
        path.move(to: CGPoint(x: 8.29346, y: 6.52817))
        path.addCurve(to: CGPoint(x: 20.7124, y: 9.80454), controlPoint1: CGPoint(x: 12.5347, y: 5.09301), controlPoint2: CGPoint(x: 17.3591, y: 6.18512))
        path.addCurve(to: CGPoint(x: 20.6587, y: 11.2137), controlPoint1: CGPoint(x: 21.0867, y: 10.2086), controlPoint2: CGPoint(x: 21.0626, y: 10.8393))
        path.addCurve(to: CGPoint(x: 19.2485, y: 11.16), controlPoint1: CGPoint(x: 20.2545, y: 11.5882), controlPoint2: CGPoint(x: 19.623, y: 11.5642))
        path.addCurve(to: CGPoint(x: 9.91065, y: 8.14633), controlPoint1: CGPoint(x: 16.7059, y: 8.4158), controlPoint2: CGPoint(x: 13.1767, y: 7.41285))
        path.addLine(to: CGPoint(x: 8.29346, y: 6.52817))
        path.close()
        return path
    }()
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
