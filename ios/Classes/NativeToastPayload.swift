import UIKit

/// Parsed MethodChannel arguments for `showToast`. Kept public so XCTest can
/// cover the native contract without driving UIKit overlays.
public struct NativeToastPayload {
    public let id: String
    public let type: String
    public let title: String
    public let subtitle: String
    public let position: String
    public let duration: TimeInterval
    public let colorARGB: UInt32?
    public let textColorARGB: UInt32?
    public let icon: String
    public let iconColorARGB: UInt32?
    public let dismissDirection: String
    public let closeButton: Bool
    public let iconAnimation: Bool

    public var shouldShow: Bool {
        !title.isEmpty || !subtitle.isEmpty
    }

    public var backgroundColor: UIColor? {
        NativeToastPayload.uiColor(from: colorARGB)
    }

    public var resolvedBackgroundColor: UIColor {
        backgroundColor ?? NativeToastPayload.defaultBackground(for: type)
    }

    public var resolvedTextColor: UIColor {
        NativeToastPayload.uiColor(from: textColorARGB)
            ?? NativeToastPayload.defaultText(for: type)
    }

    /// Icons are white on every type unless the caller picks a color.
    public var resolvedIconColor: UIColor {
        NativeToastPayload.uiColor(from: iconColorARGB) ?? .white
    }

    // Used only when the Dart side sends no id.
    private static var nextFallbackId = 0

    public static func parse(_ args: [String: Any]) -> NativeToastPayload {
        let type = args["type"] as? String ?? "success"
        let title = args["title"] as? String ?? ""
        let subtitle = args["subtitle"] as? String ?? ""
        let position = args["position"] as? String ?? "top"
        let icon = args["icon"] as? String ?? type
        let dismissDirection = args["dismissDirection"] as? String
            ?? (position == "top" ? "up" : "down")
        let duration = duration(from: args["durationMs"])
        let closeButton = args["closeButton"] as? Bool ?? (duration <= 0)
        let id: String
        if let given = args["id"] as? String {
            id = given
        } else {
            nextFallbackId += 1
            id = "native_\(nextFallbackId)"
        }
        return NativeToastPayload(
            id: id,
            type: type,
            title: title,
            subtitle: subtitle,
            position: position,
            duration: duration,
            colorARGB: argb(from: args["color"]),
            textColorARGB: argb(from: args["textColor"]),
            icon: icon,
            iconColorARGB: argb(from: args["iconColor"]),
            dismissDirection: dismissDirection,
            closeButton: closeButton,
            iconAnimation: args["iconAnimation"] as? Bool ?? true
        )
    }

    public static func duration(from durationMs: Any?) -> TimeInterval {
        guard let milliseconds = durationMs as? NSNumber else { return 4 }
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

    public static func defaultBackground(for type: String) -> UIColor {
        switch type {
        case "success": return UIColor(red: 14/255, green: 122/255, blue: 62/255, alpha: 1)
        case "error":   return UIColor(red: 209/255, green: 26/255, blue: 42/255, alpha: 1)
        case "info":    return UIColor(red: 43/255, green: 43/255, blue: 47/255, alpha: 1)
        default:        return UIColor(red: 248/255, green: 182/255, blue: 50/255, alpha: 1)
        }
    }

    /// The yellow warning background needs dark text to stay readable.
    public static func defaultText(for type: String) -> UIColor {
        switch type {
        case "success", "error", "info": return .white
        default: return UIColor(red: 26/255, green: 26/255, blue: 26/255, alpha: 1)
        }
    }
}
