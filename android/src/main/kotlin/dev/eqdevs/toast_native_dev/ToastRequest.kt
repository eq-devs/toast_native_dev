package dev.eqdevs.toast_native_dev

internal data class ToastRequest(
    val type: String,
    val title: String,
    val subtitle: String,
    val position: String,
    val durationMs: Long,
    val color: Long?,
    val icon: String,
    val iconColor: Long?,
    val dismissDirection: String,
) {
    val shouldShow: Boolean
        get() = title.isNotEmpty() || subtitle.isNotEmpty()

    companion object {
        fun from(args: Map<*, *>): ToastRequest {
            val type = args["type"] as? String ?: "success"
            val title = args["title"] as? String ?: ""
            val subtitle = args["subtitle"] as? String ?: ""
            val position = args["position"] as? String ?: "top"
            val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 2_000L
            val color = (args["color"] as? Number)?.toLong()
            val icon = args["icon"] as? String ?: type
            val iconColor = (args["iconColor"] as? Number)?.toLong()
            val dismissDirection = args["dismissDirection"] as? String
                ?: if (position == "top") "up" else "down"
            return ToastRequest(
                type = type,
                title = title,
                subtitle = subtitle,
                position = position,
                durationMs = durationMs,
                color = color,
                icon = icon,
                iconColor = iconColor,
                dismissDirection = dismissDirection,
            )
        }
    }
}
