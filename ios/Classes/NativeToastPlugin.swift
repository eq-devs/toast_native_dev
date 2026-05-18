import Flutter
import UIKit

public class NativeToastPlugin: NSObject, FlutterPlugin, UIGestureRecognizerDelegate {

    private var activeToasts: [ToastEntry] = []
    private let toastAnimationOffset: CGFloat = 100
    private let toastAnimationDuration: TimeInterval = 0.45
    private let toastAnimationDamping: CGFloat = 1.0
    private let toastAnimationInitialVelocity: CGFloat = 0.5

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
        let screenBounds = UIScreen.main.bounds
        let maxWidth = screenBounds.width - 32

        let containerView = buildToastView(type: type, message: message, color: color,
                                           icon: icon, iconColor: iconColor,
                                           maxWidth: maxWidth)
        containerView.layoutIfNeeded()
        let fittingSize = containerView.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        let toastWidth  = min(fittingSize.width, maxWidth)
        let toastHeight = max(fittingSize.height, 48)

        let stackedOffset = stackOffset(for: position, height: toastHeight)
        let marginFromEdge: CGFloat = 64
        let xPos = (screenBounds.width - toastWidth) / 2
        let yPos: CGFloat = position == "top"
            ? marginFromEdge + stackedOffset
            : screenBounds.height - marginFromEdge - toastHeight - stackedOffset

        containerView.frame = CGRect(x: xPos, y: yPos, width: toastWidth, height: toastHeight)

        let toastWindow = UIWindow(frame: screenBounds)
        toastWindow.windowLevel = UIWindow.Level.alert + 1
        toastWindow.backgroundColor = .clear
        toastWindow.isUserInteractionEnabled = true

        let rootVC = PassthroughViewController()
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = true
        toastWindow.rootViewController = rootVC
        toastWindow.makeKeyAndVisible()
        rootVC.view.addSubview(containerView)

        var entry = ToastEntry(
            window: toastWindow,
            containerView: containerView,
            position: position,
            dismissDirection: dismissDirection,
            dismissWorkItem: nil,
            timerFireDate: nil,
            remainingDuration: max(duration, 0)
        )
        activeToasts.append(entry)

        animateIn(view: containerView, position: position)
        attachGestures(to: containerView, entry: entry)

        if duration > 0 {
            scheduleTimer(forWindow: toastWindow, duration: duration)
        }
    }

    // ─── Timer scheduling / pause / resume ───────────────────────────────────

    private func scheduleTimer(forWindow window: UIWindow, duration: TimeInterval) {
        guard let idx = activeToasts.firstIndex(where: { $0.window === window }) else { return }
        let direction = activeToasts[idx].dismissDirection

        let workItem = DispatchWorkItem { [weak self, weak window] in
            guard let self = self, let win = window,
                  let current = self.activeToasts.first(where: { $0.window === win }) else { return }
            self.dismissToast(entry: current)
        }
        activeToasts[idx].dismissWorkItem = workItem
        activeToasts[idx].timerFireDate   = Date().addingTimeInterval(duration)
        activeToasts[idx].remainingDuration = duration
        _ = direction  // suppress warning
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
        container.layer.cornerRadius = 14
        container.layer.masksToBounds = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.3
        container.layer.shadowRadius = 8
        container.layer.shadowOffset = CGSize(width: 0, height: 4)

        let msgLabel = UILabel()
        msgLabel.text = message
        msgLabel.textColor = .white
        msgLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        msgLabel.numberOfLines = 0
        msgLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(msgLabel)

        var constraints: [NSLayoutConstraint] = [
            msgLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            msgLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            msgLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ]

        if let iconView = makeIconView(icon: icon, color: iconColor) {
            container.addSubview(iconView)
            constraints.append(contentsOf: [
                iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 24),
                iconView.heightAnchor.constraint(equalToConstant: 24),
                msgLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            ])
        } else {
            constraints.append(
                msgLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)
            )
        }

        NSLayoutConstraint.activate(constraints)
        return container
    }

    private func makeIconView(icon: String, color: UIColor) -> UIImageView? {
        guard icon != "none" else { return nil }

        let symbolName: String = {
            switch icon {
            case "success": return "checkmark.circle"
            case "error":   return "xmark.circle"
            default:        return "info.circle"
            }
        }()

        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: symbolName, withConfiguration: config))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }

    // ─── Enter / exit animations ─────────────────────────────────────────────

    private func animateIn(view: UIView, position: String) {
        let offset = position == "top" ? -toastAnimationOffset : toastAnimationOffset
        view.transform = CGAffineTransform(translationX: 0, y: offset)
        view.alpha = 0
        UIView.animate(
            withDuration: toastAnimationDuration,
            delay: 0,
            usingSpringWithDamping: toastAnimationDamping,
            initialSpringVelocity: toastAnimationInitialVelocity,
            options: [.curveEaseInOut],
            animations: {
                view.transform = .identity
                view.alpha = 1
            }
        )
    }

    private func animateOut(view: UIView, dismissDirection: String, completion: @escaping () -> Void) {
        let offset = dismissDirection == "up" ? -toastAnimationOffset : toastAnimationOffset
        UIView.animate(
            withDuration: toastAnimationDuration,
            delay: 0,
            usingSpringWithDamping: toastAnimationDamping,
            initialSpringVelocity: toastAnimationInitialVelocity,
            options: [.curveEaseInOut],
            animations: {
                view.transform = CGAffineTransform(translationX: 0, y: offset)
                view.alpha = 0
            },
            completion: { _ in completion() }
        )
    }

    // ─── Dismiss ─────────────────────────────────────────────────────────────

    private func dismissToast(entry: ToastEntry) {
        guard activeToasts.contains(where: { $0.window === entry.window }) else { return }
        entry.dismissWorkItem?.cancel()
        animateOut(view: entry.containerView, dismissDirection: entry.dismissDirection) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                entry.window.isHidden = true
                self.activeToasts.removeAll { $0.window === entry.window }
                self.rebuildOffsets()
            }
        }
    }

    // ─── Stacking ─────────────────────────────────────────────────────────────

    private func stackOffset(for position: String, height: CGFloat) -> CGFloat {
        activeToasts.filter { $0.position == position }
            .reduce(0) { $0 + $1.containerView.frame.height + 8 }
    }

    private func rebuildOffsets() {
        let screenBounds = UIScreen.main.bounds
        let margin: CGFloat = 64

        var topOffset = margin
        for e in activeToasts.filter({ $0.position == "top" }) {
            var frame = e.containerView.frame
            frame.origin.y = topOffset
            e.containerView.frame = frame
            topOffset += frame.height + 8
        }

        var bottomOffset = margin
        for e in activeToasts.filter({ $0.position == "bottom" }) {
            var frame = e.containerView.frame
            frame.origin.y = screenBounds.height - bottomOffset - frame.height
            e.containerView.frame = frame
            bottomOffset += frame.height + 8
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

        // Pan: visual drag + velocity-based dismiss or spring bounce-back.
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
            let velocity    = recognizer.velocity(in: superview).y
            let translation = recognizer.translation(in: superview).y
            let shouldDismiss: Bool = direction == "up"
                ? velocity < -500 || translation < -120
                : velocity >  500 || translation >  120

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
}

// ─── Associated object keys ───────────────────────────────────────────────────

private enum AssociatedKeys {
    static var entry     = "toastEntry"
    static var direction = "toastDirection"
}

// ─── Passthrough window root ──────────────────────────────────────────────────

private class PassthroughViewController: UIViewController {
    override func loadView() { view = PassthroughView() }
}

private class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
