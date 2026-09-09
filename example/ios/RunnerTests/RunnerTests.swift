import Flutter
import UIKit
import XCTest
import toast_native_dev

class RunnerTests: XCTestCase {

  func testEmptyTitleAndSubtitleIsNotShown() {
    let payload = NativeToastPayload.parse(["type": "success"])
    XCTAssertFalse(payload.shouldShow)
    XCTAssertEqual(payload.title, "")
    XCTAssertEqual(payload.subtitle, "")
  }

  func testTitleOnlyIsShown() {
    let payload = NativeToastPayload.parse(["title": "Saved"])
    XCTAssertTrue(payload.shouldShow)
    XCTAssertEqual(payload.title, "Saved")
    XCTAssertEqual(payload.subtitle, "")
  }

  func testSubtitleOnlyIsShown() {
    let payload = NativeToastPayload.parse(["subtitle": "Save your work"])
    XCTAssertTrue(payload.shouldShow)
    XCTAssertEqual(payload.title, "")
    XCTAssertEqual(payload.subtitle, "Save your work")
  }

  func testDefaultsMatchChannelContract() {
    let payload = NativeToastPayload.parse([
      "title": "Saved",
      "subtitle": "",
    ])
    XCTAssertEqual(payload.type, "success")
    XCTAssertEqual(payload.position, "top")
    XCTAssertEqual(payload.duration, 2, accuracy: 0.0001)
    XCTAssertEqual(payload.icon, "success")
    XCTAssertEqual(payload.dismissDirection, "up")
    XCTAssertNil(payload.colorARGB)
    XCTAssertNil(payload.iconColorARGB)
  }

  func testBottomPositionDefaultsDismissDirectionDown() {
    let payload = NativeToastPayload.parse([
      "title": "Saved",
      "position": "bottom",
    ])
    XCTAssertEqual(payload.dismissDirection, "down")
  }

  func testNeverDurationIsNegative() {
    let payload = NativeToastPayload.parse([
      "title": "Pinned",
      "durationMs": -1,
    ])
    XCTAssertEqual(payload.duration, -0.001, accuracy: 0.0000001)
    XCTAssertFalse(payload.duration > 0)
  }

  func testCustomOptionsAreParsed() {
    let payload = NativeToastPayload.parse([
      "type": "error",
      "title": "Offline",
      "subtitle": "Try again",
      "position": "bottom",
      "durationMs": 1500,
      "color": 0xAA112233,
      "icon": "none",
      "iconColor": 0,
      "dismissDirection": "up",
    ])
    XCTAssertEqual(payload.type, "error")
    XCTAssertEqual(payload.title, "Offline")
    XCTAssertEqual(payload.subtitle, "Try again")
    XCTAssertEqual(payload.position, "bottom")
    XCTAssertEqual(payload.duration, 1.5, accuracy: 0.0001)
    XCTAssertEqual(payload.colorARGB, 0xAA112233)
    XCTAssertEqual(payload.icon, "none")
    XCTAssertEqual(payload.iconColorARGB, 0)
    XCTAssertEqual(payload.dismissDirection, "up")
  }

  func testIconFallsBackToType() {
    let payload = NativeToastPayload.parse([
      "type": "info",
      "title": "Offline",
    ])
    XCTAssertEqual(payload.icon, "info")
  }

  func testUnknownMethodIsNotImplemented() {
    let plugin = NativeToastPlugin()
    let call = FlutterMethodCall(methodName: "nope", arguments: nil)
    let done = expectation(description: "result")
    plugin.handle(call) { result in
      XCTAssertIdentical(result as AnyObject, FlutterMethodNotImplemented as AnyObject)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }

  func testInvalidArgumentsReturnFlutterError() {
    let plugin = NativeToastPlugin()
    let call = FlutterMethodCall(methodName: "showToast", arguments: "not-a-map")
    let done = expectation(description: "result")
    plugin.handle(call) { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "INVALID_ARGS")
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
  }

  func testEmptyToastDoesNotCreateOverlay() {
    let plugin = NativeToastPlugin()
    let before = overlayWindowCount()
    let call = FlutterMethodCall(methodName: "showToast", arguments: [
      "type": "success",
      "title": "",
      "subtitle": "",
    ])
    let done = expectation(description: "result")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)
    XCTAssertEqual(overlayWindowCount(), before)
  }

  func testShowToastAddsOverlayToastView() {
    let plugin = NativeToastPlugin()
    let call = FlutterMethodCall(
      methodName: "showToast",
      arguments: [
        "type": "success",
        "title": "Saved",
        "subtitle": "Profile updated",
        "position": "top",
        "durationMs": -1,
        "color": 0xFF18A957,
        "icon": "success",
        "iconColor": 0xFFFFFFFF,
        "dismissDirection": "up",
      ]
    )
    let done = expectation(description: "result")
    plugin.handle(call) { result in
      XCTAssertNil(result)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)

    let overlay = toastOverlayWindows().first
    XCTAssertNotNil(overlay)
    XCTAssertFalse(overlay?.isHidden ?? true)
    let toastViews = overlay?.rootViewController?.view.subviews ?? []
    XCTAssertFalse(toastViews.isEmpty)
  }

  private func toastOverlayWindows() -> [UIWindow] {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .filter { $0.windowLevel > .alert }
  }

  private func overlayWindowCount() -> Int {
    toastOverlayWindows().count
  }
}
