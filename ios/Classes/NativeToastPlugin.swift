import Flutter
import UIKit

public class NativeToastPlugin: NSObject, FlutterPlugin, UIGestureRecognizerDelegate {

    // Toasts on screen (including ones playing their exit animation).
    private var activeToasts: [ToastEntry] = []
    // Single shared window hosting every toast — UIWindow is the most expensive
    // UIKit object to create, so we make one lazily and keep it for the app's
    // lifetime instead of one per toast.
    private var overlayWindow: PassthroughWindow?
    // Keyboard frame in screen coordinates, .null while it is hidden.
    private var keyboardFrame: CGRect = .null

    // Layout — kept in sync with the Android renderer.
    private let edgeMargin: CGFloat = 14
    private let toastGap: CGFloat = 8
    private let maxToastWidth: CGFloat = 520
    private let minToastHeight: CGFloat = 60

    // Motion spec — kept in sync with the Android renderer.
    private let enterDuration: TimeInterval = 0.3
    private let exitDuration: TimeInterval = 0.2
    private let exitFadeDuration: TimeInterval = 0.14   // fade ends in the first 70%
    private let reflowDuration: TimeInterval = 0.3
    private let reducedMotionDuration: TimeInterval = 0.2
    private let enterCurve = (CGPoint(x: 0.2, y: 0), CGPoint(x: 0, y: 1))
    private let exitCurve = (CGPoint(x: 0.3, y: 0), CGPoint(x: 1, y: 1))

    // Gestures.
    private let dismissThreshold: CGFloat = 56
    private let flickVelocity: CGFloat = 800      // pt/s toward the dismiss edge
    private let reverseVelocity: CGFloat = 100    // pt/s back toward rest
    private let rubberBand: CGFloat = 0.18        // wrong-direction drag follows 18%
    private let armedAlpha: CGFloat = 0.6
    private let settleDamping: CGFloat = 0.85

    // Timers.
    private let resumeGrace: TimeInterval = 1.5
    private let voiceOverMinDuration: TimeInterval = 6

    struct ToastEntry {
        let id: String
        let containerView: UIView
        var position: String
        var dismissDirection: String
        var dismissWorkItem: DispatchWorkItem?
        var timerFireUptime: TimeInterval?   // nil when paused or length == "never"
        var remainingDuration: TimeInterval  // updated on pause
        var isDismissing = false             // exit animation running
    }

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                           name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
        center.addObserver(self, selector: #selector(contentSizeCategoryDidChange(_:)),
                           name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    // MethodChannel callbacks already arrive on the main thread.
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showToast":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected a dictionary", details: nil))
                return
            }
            let payload = NativeToastPayload.parse(args)
            if payload.shouldShow {
                show(payload)
            }
            result(nil)

        case "dismissToast":
            guard let id = (call.arguments as? [String: Any])?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected a string id", details: nil))
                return
            }
            for entry in activeToasts where entry.id == id {
                dismissToast(view: entry.containerView)
            }
            result(nil)

        case "dismissAll":
            for entry in activeToasts {
                dismissToast(view: entry.containerView)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─── Toast presentation ───────────────────────────────────────────────────

    private func edge(of position: String) -> String {
        position == "top" ? "top" : "bottom"
    }

    private func show(_ payload: NativeToastPayload) {
        // Same id already on screen: update it in place and restart its timer.
        if let idx = activeToasts.firstIndex(where: { $0.id == payload.id && !$0.isDismissing }) {
            update(entryAt: idx, with: payload)
        } else {
            present(payload)
        }
    }

    private func present(_ payload: NativeToastPayload) {
        guard let toastWindow = presentationWindow(),
              let rootView = toastWindow.rootViewController?.view else { return }

        let toastView = ToastView(payload: payload)
        toastView.onClose = { [weak self, weak toastView] in
            guard let self = self, let toastView = toastView else { return }
            self.dismissToast(view: toastView)
        }
        rootView.addSubview(toastView)

        activeToasts.append(ToastEntry(
            id: payload.id,
            containerView: toastView,
            position: payload.position,
            dismissDirection: payload.dismissDirection,
            dismissWorkItem: nil,
            timerFireUptime: nil,
            remainingDuration: max(payload.duration, 0)
        ))

        resize(toastView, in: rootView)
        // The new toast is placed directly; its neighbours slide to make room.
        layoutStack(animated: true, placing: toastView)
        animateIn(view: toastView, position: payload.position)
        if payload.iconAnimation { toastView.playIconEntrance() }
        attachGestures(to: toastView)
        startTimer(forView: toastView, duration: payload.duration)
        announce(toastView)
    }

    private func update(entryAt idx: Int, with payload: NativeToastPayload) {
        guard let toastView = activeToasts[idx].containerView as? ToastView,
              let rootView = toastView.superview else { return }
        activeToasts[idx].dismissWorkItem?.cancel()
        activeToasts[idx].dismissWorkItem = nil
        activeToasts[idx].timerFireUptime = nil
        activeToasts[idx].remainingDuration = max(payload.duration, 0)
        activeToasts[idx].position = payload.position
        activeToasts[idx].dismissDirection = payload.dismissDirection

        toastView.configure(with: payload)
        if payload.iconAnimation { toastView.playIconEntrance() }
        resize(toastView, in: rootView)
        layoutStack(animated: true)
        startTimer(forView: toastView, duration: payload.duration)
        announce(toastView)
    }

    // Screen readers get the message the moment it appears, so reading it never
    // depends on how long the toast stays visible.
    private func announce(_ toastView: ToastView) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: toastView.spokenText)
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
        // Rotation, split view and safe-area changes re-lay out visible toasts.
        (rootVC.view as? PassthroughView)?.onGeometryChange = { [weak self] in
            self?.relayoutAll()
        }
        window.rootViewController = rootVC
        window.isHidden = false
        overlayWindow = window
        return window
    }

    // ─── Layout ───────────────────────────────────────────────────────────────

    private struct StackMetrics {
        let width: CGFloat
        let centerX: CGFloat
        let top: CGFloat      // y of the first top toast's upper edge
        let bottom: CGFloat   // y of the first bottom toast's lower edge
    }

    private func stackMetrics(in rootView: UIView) -> StackMetrics {
        let bounds = rootView.bounds
        let keyWindow = rootView.window?.windowScene?.windows.first(where: { $0.isKeyWindow })
        let safe = keyWindow?.safeAreaInsets ?? rootView.safeAreaInsets
        let safeWidth = bounds.width - safe.left - safe.right

        // Bottom toasts sit above the keyboard while it is showing.
        var keyboardOverlap: CGFloat = 0
        if !keyboardFrame.isNull {
            let frameInView = rootView.convert(keyboardFrame, from: nil)
            keyboardOverlap = max(0, bounds.maxY - frameInView.minY)
        }

        return StackMetrics(
            width: max(0, min(safeWidth - edgeMargin * 2, maxToastWidth)),
            centerX: safe.left + safeWidth / 2,
            top: safe.top + edgeMargin,
            bottom: bounds.height - max(safe.bottom, keyboardOverlap) - edgeMargin
        )
    }

    private func resize(_ toastView: ToastView, in rootView: UIView) {
        let width = stackMetrics(in: rootView).width
        let height = max(toastView.fittingHeight(forWidth: width), minToastHeight)
        toastView.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    }

    // Positions every toast that is not on its way out. Positions are set
    // through `center`, never `frame`, because a drag may have set a transform.
    private func layoutStack(animated: Bool, placing newView: UIView? = nil) {
        guard let rootView = overlayWindow?.rootViewController?.view else { return }
        let metrics = stackMetrics(in: rootView)

        var topY = metrics.top
        for entry in activeToasts where edge(of: entry.position) == "top" && !entry.isDismissing {
            let view = entry.containerView
            let height = view.bounds.height
            move(view, to: CGPoint(x: metrics.centerX, y: topY + height / 2),
                 animated: animated && view !== newView)
            topY += height + toastGap
        }

        // Reversed so the newest bottom toast is closest to the bottom edge.
        var bottomY = metrics.bottom
        for entry in activeToasts.reversed()
        where edge(of: entry.position) == "bottom" && !entry.isDismissing {
            let view = entry.containerView
            let height = view.bounds.height
            move(view, to: CGPoint(x: metrics.centerX, y: bottomY - height / 2),
                 animated: animated && view !== newView)
            bottomY -= height + toastGap
        }
    }

    private func move(_ view: UIView, to target: CGPoint, animated: Bool) {
        if abs(view.center.x - target.x) < 0.5 && abs(view.center.y - target.y) < 0.5 { return }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            view.center = target
            return
        }
        UIViewPropertyAnimator(
            duration: reflowDuration, controlPoint1: enterCurve.0, controlPoint2: enterCurve.1
        ) {
            view.center = target
        }.startAnimation()
    }

    // Re-measures and repositions everything, e.g. after rotation, a safe-area
    // change or a Dynamic Type change.
    private func relayoutAll() {
        guard let rootView = overlayWindow?.rootViewController?.view else { return }
        for entry in activeToasts {
            if let toastView = entry.containerView as? ToastView {
                resize(toastView, in: rootView)
            }
        }
        layoutStack(animated: false)
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
            .cgRectValue else { return }
        keyboardFrame = frame
        layoutStack(animated: true)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardFrame = .null
        layoutStack(animated: true)
    }

    @objc private func contentSizeCategoryDidChange(_ note: Notification) {
        // Let the labels pick up their new fonts first.
        DispatchQueue.main.async { [weak self] in self?.relayoutAll() }
    }

    // ─── Timer scheduling / pause / resume ───────────────────────────────────

    private func startTimer(forView view: UIView, duration: TimeInterval) {
        guard duration > 0 else { return }
        // VoiceOver users need time to reach the toast after hearing it.
        let effective = UIAccessibility.isVoiceOverRunning
            ? max(duration, voiceOverMinDuration) : duration
        scheduleTimer(forView: view, duration: effective)
    }

    private func scheduleTimer(forView view: UIView, duration: TimeInterval) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }) else { return }

        let workItem = DispatchWorkItem { [weak self, weak view] in
            guard let self = self, let view = view else { return }
            self.dismissToast(view: view)
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
        // Kept strictly positive so resume can tell a paused timer from "never".
        activeToasts[idx].remainingDuration =
            max(fireUptime - ProcessInfo.processInfo.systemUptime, 0.001)
        activeToasts[idx].timerFireUptime = nil
    }

    private func resumeTimer(forView view: UIView) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }) else { return }
        guard !activeToasts[idx].isDismissing else { return }
        guard activeToasts[idx].timerFireUptime == nil else { return } // already running
        let remaining = activeToasts[idx].remainingDuration
        guard remaining > 0 else { return } // "never" toast — don't reschedule
        // After a touch (hold or cancelled swipe) the toast stays long enough
        // that letting go never looks like it dismissed the toast.
        scheduleTimer(forView: view, duration: max(remaining, resumeGrace))
    }

    // ─── Enter / exit animations ─────────────────────────────────────────────

    private func animateIn(view: UIView, position: String) {
        view.alpha = 0
        if UIAccessibility.isReduceMotionEnabled {
            UIViewPropertyAnimator(duration: reducedMotionDuration, curve: .linear) {
                view.alpha = 1
            }.startAnimation()
            return
        }
        // Slide in from the toast's own height plus the gap, from its edge.
        let distance = view.bounds.height + toastGap
        let offset = edge(of: position) == "top" ? -distance : distance
        view.transform = CGAffineTransform(translationX: 0, y: offset)
        UIViewPropertyAnimator(
            duration: enterDuration, controlPoint1: enterCurve.0, controlPoint2: enterCurve.1
        ) {
            view.transform = .identity
            view.alpha = 1
        }.startAnimation()
    }

    // Slides out toward the dismiss direction, starting from wherever the toast
    // currently is (possibly mid-drag). `velocity` is the finger's release
    // velocity for a swipe; nil for a timed or programmatic dismissal.
    private func animateOut(view: UIView, dismissDirection: String, velocity: CGFloat?,
                            completion: @escaping () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            let fade = UIViewPropertyAnimator(duration: reducedMotionDuration, curve: .linear) {
                view.alpha = 0
            }
            fade.addCompletion { _ in completion() }
            fade.startAnimation()
            return
        }

        let distance = view.bounds.height + toastGap
        let delta = dismissDirection == "up" ? -distance : distance
        let target = CGAffineTransform(translationX: 0, y: view.transform.ty + delta)

        if let velocity = velocity {
            // Continue from the finger's speed instead of restarting from rest.
            UIView.animate(
                withDuration: exitDuration + 0.05, delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: min(abs(velocity) / distance, 30),
                options: [.beginFromCurrentState],
                animations: {
                    view.transform = target
                    view.alpha = 0
                },
                completion: { _ in completion() }
            )
            return
        }

        let slide = UIViewPropertyAnimator(
            duration: exitDuration, controlPoint1: exitCurve.0, controlPoint2: exitCurve.1
        ) {
            view.transform = target
        }
        slide.addCompletion { _ in completion() }
        slide.startAnimation()
        UIViewPropertyAnimator(duration: exitFadeDuration, curve: .linear) {
            view.alpha = 0
        }.startAnimation()
    }

    // ─── Dismiss ─────────────────────────────────────────────────────────────

    private func dismissToast(view: UIView, velocity: CGFloat? = nil) {
        guard let idx = activeToasts.firstIndex(where: { $0.containerView === view }),
              !activeToasts[idx].isDismissing else { return }
        activeToasts[idx].dismissWorkItem?.cancel()
        activeToasts[idx].dismissWorkItem = nil
        activeToasts[idx].timerFireUptime = nil
        activeToasts[idx].isDismissing = true
        let dismissDirection = activeToasts[idx].dismissDirection

        // Lock out further touches so an active pan/hold can't keep writing
        // .transform mid-animation and fight the slide-off.
        view.isUserInteractionEnabled = false
        // Neighbours close the gap while the toast leaves, not after.
        layoutStack(animated: true)
        animateOut(view: view, dismissDirection: dismissDirection, velocity: velocity) { [weak self] in
            view.removeFromSuperview()
            guard let self = self else { return }
            self.activeToasts.removeAll { $0.containerView === view }
            if self.activeToasts.isEmpty {
                self.overlayWindow?.isHidden = true
            }
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

        // Pan: visual drag, then dismiss or spring back on release.
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

    // Leave touches on the close button to the button itself.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool { !(touch.view is UIControl) }

    // ─── Gesture handlers ─────────────────────────────────────────────────────

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        guard let view = recognizer.view as? ToastView else { return }
        switch recognizer.state {
        case .began:
            pauseTimer(forView: view)
            view.setPressed(true)
        case .ended, .cancelled, .failed:
            resumeTimer(forView: view)
            view.setPressed(false)
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view as? ToastView,
              let entry = activeToasts.first(where: { $0.containerView === view }),
              !entry.isDismissing
        else { return }
        // +1 when the toast dismisses downward, -1 upward.
        let sign: CGFloat = entry.dismissDirection == "up" ? -1 : 1

        switch recognizer.state {
        case .began:
            // Grab the toast wherever it is on screen, even mid spring-back.
            let current = view.layer.presentation()?.affineTransform().ty ?? view.transform.ty
            view.removeTransformAnimations()
            view.transform = CGAffineTransform(translationX: 0, y: current)
            view.panStartRaw = current * sign >= 0 ? current : current / rubberBand
            view.isArmed = false

        case .changed:
            let raw = view.panStartRaw + recognizer.translation(in: view.superview).y
            // Free movement toward the dismiss edge, rubber-band the other way.
            let offset = raw * sign >= 0 ? raw : raw * rubberBand
            view.transform = CGAffineTransform(translationX: 0, y: offset)
            // Fade toward armedAlpha as the drag nears the threshold, so the
            // user can see whether letting go will dismiss.
            let progress = min(max(offset * sign / dismissThreshold, 0), 1)
            view.alpha = 1 - (1 - armedAlpha) * progress

            let nowArmed = offset * sign > dismissThreshold
            if nowArmed && !view.isArmed {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            view.isArmed = nowArmed

        case .ended:
            let velocity = recognizer.velocity(in: view.superview).y
            let toward = view.transform.ty * sign
            let towardVelocity = velocity * sign
            // Release direction wins over distance: a flick toward the edge
            // dismisses, moving back toward rest cancels.
            let shouldDismiss: Bool
            if towardVelocity > flickVelocity && toward > 0 {
                shouldDismiss = true
            } else if towardVelocity < -reverseVelocity {
                shouldDismiss = false
            } else {
                shouldDismiss = toward > dismissThreshold
            }
            view.isArmed = false
            if shouldDismiss {
                dismissToast(view: view, velocity: velocity)
            } else {
                springBack(view, velocity: velocity)
            }

        case .cancelled:
            view.isArmed = false
            springBack(view, velocity: 0)

        default:
            break
        }
    }

    // Returns a cancelled drag to rest, starting from the finger's velocity.
    // .allowUserInteraction keeps the toast grabbable while it settles.
    private func springBack(_ view: UIView, velocity: CGFloat) {
        let offset = view.transform.ty
        let normalizedVelocity: CGFloat = abs(offset) > 0.5
            ? min(max(velocity / -offset, -30), 30) : 0
        UIView.animate(
            withDuration: 0.4, delay: 0,
            usingSpringWithDamping: settleDamping,
            initialSpringVelocity: normalizedVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            view.transform = .identity
            view.alpha = 1
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    private func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
    }
}

// ─── Toast view ───────────────────────────────────────────────────────────────

// The outer view carries position, drag translation and opacity. The inner
// `card` carries the background, shadow and press scale, so the two transforms
// never interfere.
private final class ToastView: UIView {
    private let card = UIView()
    private let contentStack = UIStackView()
    private var widthConstraint: NSLayoutConstraint!
    private weak var iconView: ToastIconView?

    var onClose: (() -> Void)?
    // Drag bookkeeping, owned by the pan handler.
    var panStartRaw: CGFloat = 0
    var isArmed = false

    private(set) var spokenText = ""

    init(payload: NativeToastPayload) {
        super.init(frame: .zero)

        card.layer.cornerRadius = 16
        card.layer.masksToBounds = false
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.10
        card.layer.shadowRadius = 4
        card.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(card)

        // Toast content metrics are kept in sync with the Android renderer.
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 16, bottom: 12, trailing: 16
        )
        card.addSubview(contentStack)

        widthConstraint = card.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: card.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            widthConstraint,
        ])

        configure(with: payload)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with payload: NativeToastPayload) {
        for subview in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let background = payload.resolvedBackgroundColor
        let textColor = payload.resolvedTextColor
        card.backgroundColor = background

        if payload.icon != "none" {
            let iconView = ToastIconView(
                type: payload.icon, iconColor: payload.resolvedIconColor, glyphColor: background
            )
            iconView.translatesAutoresizingMaskIntoConstraints = false
            self.iconView = iconView
            contentStack.addArrangedSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 24),
                iconView.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 0
        if !payload.title.isEmpty {
            let titleLabel = makeLabel(
                text: payload.title, color: textColor, lines: 2,
                font: UIFont.systemFont(ofSize: 14, weight: .semibold), style: .subheadline
            )
            titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            textStack.addArrangedSubview(titleLabel)
        }
        if !payload.subtitle.isEmpty {
            textStack.addArrangedSubview(makeLabel(
                text: payload.subtitle, color: textColor, lines: 3,
                font: UIFont.systemFont(ofSize: 13, weight: .regular), style: .footnote
            ))
        }
        contentStack.addArrangedSubview(textStack)

        if payload.closeButton {
            let closeButton = ToastCloseButton(color: textColor)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            contentStack.addArrangedSubview(closeButton)
            NSLayoutConstraint.activate([
                closeButton.widthAnchor.constraint(equalToConstant: 24),
                closeButton.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        spokenText = [payload.title, payload.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        if payload.closeButton {
            // Labels and the close button are reached individually.
            isAccessibilityElement = false
            accessibilityCustomActions = nil
        } else {
            // One element with a dismiss action, so VoiceOver users never
            // depend on the swipe gesture.
            isAccessibilityElement = true
            accessibilityLabel = spokenText
            accessibilityTraits = .staticText
            accessibilityCustomActions = [UIAccessibilityCustomAction(
                name: "Dismiss", target: self, selector: #selector(accessibilityDismiss)
            )]
        }
    }

    // Fonts keep their designed size at the default setting and scale with
    // Dynamic Type from there.
    private func makeLabel(text: String, color: UIColor, lines: Int,
                           font: UIFont, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func fittingHeight(forWidth width: CGFloat) -> CGFloat {
        widthConstraint.constant = width
        return card.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds/center rather than frame: the card may be scaled while pressed.
        card.bounds = bounds
        card.center = CGPoint(x: bounds.midX, y: bounds.midY)
        // An explicit path lets Core Animation skip the offscreen pass it would
        // otherwise need to derive the shadow shape on every animated frame.
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds, cornerRadius: card.layer.cornerRadius
        ).cgPath
    }

    func playIconEntrance() {
        iconView?.playEntrance()
    }

    // Slight scale-down while held, showing that the timer is paused.
    func setPressed(_ pressed: Bool) {
        UIView.animate(
            withDuration: pressed ? 0.12 : 0.18, delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]
        ) {
            self.card.transform = pressed
                ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        }
    }

    // Stops in-flight translation animations so a new drag owns the transform.
    func removeTransformAnimations() {
        for key in layer.animationKeys() ?? [] {
            if let animation = layer.animation(forKey: key) as? CAPropertyAnimation,
               animation.keyPath == "transform" {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func accessibilityDismiss() -> Bool {
        onClose?()
        return true
    }
}

// ─── Close button ─────────────────────────────────────────────────────────────

private final class ToastCloseButton: UIControl {
    private let color: UIColor

    init(color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "Dismiss"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Drawn at 24pt to match the icon, but the touch target is 40pt.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let s = min(rect.width, rect.height) / 24
        context.scaleBy(x: s, y: s)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.75)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 7.5, y: 7.5))
        context.addLine(to: CGPoint(x: 16.5, y: 16.5))
        context.move(to: CGPoint(x: 16.5, y: 7.5))
        context.addLine(to: CGPoint(x: 7.5, y: 16.5))
        context.strokePath()
    }
}

// ─── Toast icon ───────────────────────────────────────────────────────────────

// ─── Icon motion ──────────────────────────────────────────────────────────────
// Every icon shares one entrance (a springy pop of the badge), then plays a
// motion that fits its meaning:
//   success — the check draws left to right, then the badge bounces
//   error   — the cross bursts out from its centre, then the badge shakes
//   warning — the "!" drops in and its dot pops, then the badge wobbles
//   info    — the dot pops, the stem grows down, then one soft pulse
//   offline — the slash strikes through the WiFi symbol
// Everything is a pure function of elapsed milliseconds, so the Android
// renderer uses exactly the same numbers.
private enum IconMotion {
    static let totalMs: Double = 1000

    static func seg(_ ms: Double, _ start: Double, _ end: Double) -> Double {
        min(max((ms - start) / (end - start), 0), 1)
    }

    static func easeOutCubic(_ x: Double) -> Double {
        let inv = 1 - x
        return 1 - inv * inv * inv
    }

    // Overshoots past 1 before settling, like a light spring.
    static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let d = x - 1
        return 1 + c3 * d * d * d + c1 * d * d
    }

    // 0 → 1 → 0.
    static func bump(_ x: Double) -> Double { sin(.pi * x) }

    // A wave that fades to rest: used for the shake and the wobble.
    static func decayingWave(_ x: Double, cycles: Double) -> Double {
        (1 - x) * sin(x * cycles * 2 * .pi)
    }

    static func kind(for type: String) -> String {
        switch type {
        case "success", "error", "warning", "offline": return type
        default: return "info"
        }
    }

    static func alpha(_ ms: Double) -> Double { seg(ms, 80, 200) }

    static func scale(_ kind: String, _ ms: Double) -> Double {
        let pop = 0.5 + 0.5 * easeOutBack(seg(ms, 80, 380))
        let accent: Double
        switch kind {
        case "success": accent = 1 + 0.18 * bump(seg(ms, 430, 730))
        case "info":    accent = 1 + 0.10 * bump(seg(ms, 520, 820))
        default:        accent = 1
        }
        return pop * accent
    }

    // Horizontal shake in 24-unit icon space.
    static func shake(_ kind: String, _ ms: Double) -> Double {
        kind == "error" ? 3 * decayingWave(seg(ms, 380, 780), cycles: 3) : 0
    }

    // Wobble in degrees.
    static func tilt(_ kind: String, _ ms: Double) -> Double {
        kind == "warning" ? 14 * decayingWave(seg(ms, 430, 930), cycles: 2.5) : 0
    }
}

// All icons are built from shape layers in a 24-unit canvas that is scaled to
// the view, so each part of the glyph can be animated on its own.
private class ToastIconView: UIView {
    private let kind: String
    private let iconColor: UIColor
    private let glyphColor: UIColor

    // Carries the whole-badge motion (pop, bounce, shake, wobble).
    private let effects = CALayer()
    private let canvas = CALayer()
    // Strokes that draw themselves on.
    private var strokeLayers: [CAShapeLayer] = []
    // The stem of "!", which drops in instead of drawing.
    private var dropLayer: CAShapeLayer?
    // The dot of "!" / "i".
    private var dotLayer: CAShapeLayer?

    init(type: String, iconColor: UIColor, glyphColor: UIColor) {
        self.kind = IconMotion.kind(for: type)
        self.iconColor = iconColor
        self.glyphColor = glyphColor
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        canvas.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        layer.addSublayer(effects)
        effects.addSublayer(canvas)
        buildShapes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = min(bounds.width, bounds.height) / 24
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effects.bounds = bounds
        effects.position = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.position = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        CATransaction.commit()
    }

    // ─── Shapes ───────────────────────────────────────────────────────────────

    private func buildShapes() {
        if kind == "offline" {
            addFill(ToastIconView.wifiFillPath, color: iconColor)
            addFill(circlePath(center: CGPoint(x: 12.041, y: 18.8081), radius: 1.27515),
                    color: iconColor)
            strokeLayers.append(addStroke(
                linePath([CGPoint(x: 4.23901, y: 4.16736), CGPoint(x: 18.4817, y: 18.4104)]),
                color: iconColor, width: 1.3301
            ))
            return
        }

        addFill(circlePath(center: CGPoint(x: 12, y: 12), radius: 10.75), color: iconColor)

        switch kind {
        case "success":
            strokeLayers.append(addStroke(linePath([
                CGPoint(x: 8.5, y: 12.5), CGPoint(x: 10.5, y: 14.5), CGPoint(x: 15.5, y: 9.5),
            ]), color: glyphColor))
        case "error":
            // Four arms from the centre, so they can burst out together.
            let center = CGPoint(x: 12, y: 12)
            for tip in [CGPoint(x: 14.5, y: 9.5), CGPoint(x: 9.5, y: 14.5),
                        CGPoint(x: 9.5, y: 9.5), CGPoint(x: 14.5, y: 14.5)] {
                strokeLayers.append(addStroke(linePath([center, tip]), color: glyphColor))
            }
        case "warning":
            dropLayer = addStroke(
                linePath([CGPoint(x: 12, y: 7.5), CGPoint(x: 12, y: 13)]), color: glyphColor
            )
            addDot(center: CGPoint(x: 12, y: 16.25))
        default:
            addDot(center: CGPoint(x: 12, y: 7.75))
            strokeLayers.append(addStroke(
                linePath([CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 16.5)]), color: glyphColor
            ))
        }
    }

    private func circlePath(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2))
    }

    private func linePath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func addFill(_ path: UIBezierPath, color: UIColor) {
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.fillColor = color.cgColor
        canvas.addSublayer(shape)
    }

    @discardableResult
    private func addStroke(_ path: UIBezierPath, color: UIColor, width: CGFloat = 1.5) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        canvas.addSublayer(shape)
        return shape
    }

    // The dot gets its own bounds so it can scale around its centre.
    private func addDot(center: CGPoint) {
        let shape = CAShapeLayer()
        shape.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        shape.position = center
        shape.path = UIBezierPath(ovalIn: shape.bounds).cgPath
        shape.fillColor = glyphColor.cgColor
        canvas.addSublayer(shape)
        dotLayer = shape
    }

    // ─── Entrance ─────────────────────────────────────────────────────────────

    func playEntrance() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        typealias M = IconMotion
        let kind = self.kind
        let unit = Double(min(bounds.width, bounds.height) / 24)   // points per icon unit

        // Whole badge.
        animate(effects, "opacity") { M.alpha($0) }
        animate(effects, "transform.scale") { M.scale(kind, $0) }
        if kind == "error" {
            animate(effects, "transform.translation.x") { M.shake(kind, $0) * (unit > 0 ? unit : 1) }
        }
        if kind == "warning" {
            animate(effects, "transform.rotation.z") { M.tilt(kind, $0) * .pi / 180 }
        }

        // Glyph parts.
        switch kind {
        case "success":
            for stroke in strokeLayers {
                animate(stroke, "strokeEnd") { M.easeOutCubic(M.seg($0, 200, 480)) }
            }
        case "error":
            for stroke in strokeLayers {
                animate(stroke, "strokeEnd") { M.easeOutCubic(M.seg($0, 200, 400)) }
            }
        case "warning":
            if let stem = dropLayer {
                animate(stem, "transform.translation.y") {
                    -6 * (1 - M.easeOutBack(M.seg($0, 200, 450)))
                }
                animate(stem, "opacity") { M.seg($0, 200, 300) }
            }
            if let dot = dotLayer {
                animate(dot, "transform.scale") { max(M.easeOutBack(M.seg($0, 400, 560)), 0) }
            }
        case "offline":
            for stroke in strokeLayers {
                animate(stroke, "strokeEnd") { M.easeOutCubic(M.seg($0, 200, 580)) }
            }
        default:
            if let dot = dotLayer {
                animate(dot, "transform.scale") { max(M.easeOutBack(M.seg($0, 200, 360)), 0) }
            }
            for stroke in strokeLayers {
                animate(stroke, "strokeEnd") { M.easeOutCubic(M.seg($0, 300, 520)) }
            }
        }
    }

    // Samples `value(ms)` across the whole motion at 60 fps. Every function
    // ends on the layer's resting value, so nothing jumps when it finishes.
    private func animate(_ target: CALayer, _ keyPath: String, _ value: (Double) -> Double) {
        let frames = Int(IconMotion.totalMs / 1000 * 60)
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...frames).map { frame in
            value(Double(frame) / Double(frames) * IconMotion.totalMs)
        }
        animation.duration = IconMotion.totalMs / 1000
        animation.calculationMode = .linear
        target.add(animation, forKey: "entrance." + keyPath)
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
    // Called when the view's size or safe area changes (rotation, split view).
    var onGeometryChange: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onGeometryChange?()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onGeometryChange?()
    }
}
