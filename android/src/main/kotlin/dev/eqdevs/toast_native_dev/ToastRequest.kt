package dev.eqdevs.toast_native_dev

internal data class ToastRequest(
    val id: String,
    val type: String,
    val title: String,
    val subtitle: String,
    val position: String,
    val durationMs: Long,
    val color: Long?,
    val textColor: Long?,
    val icon: String,
    val iconColor: Long?,
    val dismissDirection: String,
    val closeButton: Boolean,
    val iconAnimation: Boolean,
) {
    val shouldShow: Boolean
        get() = title.isNotEmpty() || subtitle.isNotEmpty()

    companion object {
        // Used only when the Dart side sends no id.
        private var nextFallbackId = 0L

        fun from(args: Map<*, *>): ToastRequest {
            val type = args["type"] as? String ?: "success"
            val title = args["title"] as? String ?: ""
            val subtitle = args["subtitle"] as? String ?: ""
            val position = args["position"] as? String ?: "top"
            val durationMs = (args["durationMs"] as? Number)?.toLong() ?: 4_000L
            val color = (args["color"] as? Number)?.toLong()
            val textColor = (args["textColor"] as? Number)?.toLong()
            val icon = args["icon"] as? String ?: type
            val iconColor = (args["iconColor"] as? Number)?.toLong()
            val dismissDirection = args["dismissDirection"] as? String
                ?: if (position == "top") "up" else "down"
            val closeButton = args["closeButton"] as? Boolean ?: (durationMs <= 0)
            val iconAnimation = args["iconAnimation"] as? Boolean ?: true
            val id = args["id"] as? String ?: "native_${++nextFallbackId}"
            return ToastRequest(
                id = id,
                type = type,
                title = title,
                subtitle = subtitle,
                position = position,
                durationMs = durationMs,
                color = color,
                textColor = textColor,
                icon = icon,
                iconColor = iconColor,
                dismissDirection = dismissDirection,
                closeButton = closeButton,
                iconAnimation = iconAnimation,
            )
        }
    }
}
