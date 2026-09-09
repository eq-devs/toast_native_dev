package dev.eqdevs.toast_native_dev

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ToastRequestTest {

    @Test
    fun emptyTitleAndSubtitleIsNotShown() {
        val request = ToastRequest.from(mapOf("type" to "success"))
        assertFalse(request.shouldShow)
        assertEquals("", request.title)
        assertEquals("", request.subtitle)
    }

    @Test
    fun titleOnlyIsShown() {
        val request = ToastRequest.from(mapOf("title" to "Saved"))
        assertTrue(request.shouldShow)
        assertEquals("Saved", request.title)
        assertEquals("", request.subtitle)
    }

    @Test
    fun subtitleOnlyIsShown() {
        val request = ToastRequest.from(mapOf("subtitle" to "Save your work"))
        assertTrue(request.shouldShow)
        assertEquals("", request.title)
        assertEquals("Save your work", request.subtitle)
    }

    @Test
    fun defaultsMatchChannelContract() {
        val request = ToastRequest.from(
            mapOf(
                "title" to "Saved",
                "subtitle" to "",
            )
        )
        assertEquals("success", request.type)
        assertEquals("top", request.position)
        assertEquals(2_000L, request.durationMs)
        assertEquals("success", request.icon)
        assertEquals("up", request.dismissDirection)
        assertNull(request.color)
        assertNull(request.iconColor)
    }

    @Test
    fun bottomPositionDefaultsDismissDirectionDown() {
        val request = ToastRequest.from(
            mapOf(
                "title" to "Saved",
                "position" to "bottom",
            )
        )
        assertEquals("down", request.dismissDirection)
    }

    @Test
    fun neverDurationIsMinusOne() {
        val request = ToastRequest.from(
            mapOf(
                "title" to "Pinned",
                "durationMs" to -1,
            )
        )
        assertEquals(-1L, request.durationMs)
        assertTrue(request.durationMs <= 0)
    }

    @Test
    fun customOptionsAreParsed() {
        val request = ToastRequest.from(
            mapOf(
                "type" to "error",
                "title" to "Offline",
                "subtitle" to "Try again",
                "position" to "bottom",
                "durationMs" to 1500,
                "color" to 0xAA112233,
                "icon" to "none",
                "iconColor" to 0,
                "dismissDirection" to "up",
            )
        )
        assertEquals("error", request.type)
        assertEquals("Offline", request.title)
        assertEquals("Try again", request.subtitle)
        assertEquals("bottom", request.position)
        assertEquals(1_500L, request.durationMs)
        assertEquals(0xAA112233L, request.color)
        assertEquals("none", request.icon)
        assertEquals(0L, request.iconColor)
        assertEquals("up", request.dismissDirection)
    }

    @Test
    fun iconFallsBackToType() {
        val request = ToastRequest.from(
            mapOf(
                "type" to "info",
                "title" to "Offline",
            )
        )
        assertEquals("info", request.icon)
    }
}
