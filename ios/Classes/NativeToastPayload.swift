import UIKit

/// Parsed MethodChannel arguments for `showToast`. Kept public so XCTest can
/// cover the native contract without driving UIKit overlays.
public struct NativeToastPayload {
    public let type: String
    public let title: String
    public let subtitle: String
    public let position: String
    public let duration: TimeInterval
    public let colorARGB: UInt32?
    public let icon: String
    public let iconColorARGB: UInt32?
    public let dismissDirection: String

    public var shouldShow: Bool {
        !title.isEmpty || !subtitle.isEmpty
    }

    public var backgroundColor: UIColor? {
        NativeToastPayload.uiColor(from: colorARGB)
    }

    public var resolvedIconColor: UIColor {
        NativeToastPayload.uiColor(from: iconColorARGB) ?? .white
    }

    public static func parse(_ args: [String: Any]) -> NativeToastPayload {
        let type = args["type"] as? String ?? "success"
        let title = args["title"] as? String ?? ""
        let subtitle = args["subtitle"] as? String ?? ""
        let position = args["position"] as? String ?? "top"
        let icon = args["icon"] as? String ?? type
        let dismissDirection = args["dismissDirection"] as? String
            ?? (position == "top" ? "up" : "down")
        return NativeToastPayload(
            type: type,
            title: title,
            subtitle: subtitle,
            position: position,
            duration: duration(from: args["durationMs"]),
            colorARGB: argb(from: args["color"]),
            icon: icon,
            iconColorARGB: argb(from: args["iconColor"]),
            dismissDirection: dismissDirection
        )
    }

    public static func duration(from durationMs: Any?) -> TimeInterval {
        guard let milliseconds = durationMs as? NSNumber else { return 2 }
        return milliseconds.doubleValue / 1000
    }

    public static func argb(from value: Any?) -> UInt32? {
        guard let number = value as? NSNumber else { return nil }
        return number.uint32Value
    }

    public static func uiColor(from argb: UInt32?) -> UIColor? {
        guard let argb else { return nil }
        return UIColor(
            red: CGFloat((argb >> 16) & 0xff) / 255,
            green: CGFloat((argb >> 8) & 0xff) / 255,
            blue: CGFloat(argb & 0xff) / 255,
            alpha: CGFloat((argb >> 24) & 0xff) / 255
        )
    }
}
