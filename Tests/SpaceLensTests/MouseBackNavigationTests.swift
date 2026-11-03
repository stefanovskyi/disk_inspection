import AppKit
import SwiftUI
import XCTest
@testable import SpaceLens

@MainActor
final class MouseBackNavigationTests: XCTestCase {
    func testDriverGeneratedBackSwipeNavigatesThroughTheWindowMonitor() {
        let (window, view) = makeWindow()
        defer { close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }
        let swipe = NavigationSwipeEvent(deltaX: 1, deltaY: 0, window: window)

        // Logi Options+ can replace the physical button with this native event.
        NSApp.sendEvent(swipe)
        XCTAssertEqual(backCount, 1)
    }

    func testForwardAndVerticalSwipesPassThrough() {
        let (window, view) = makeWindow()
        defer { close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }

        for (x, y): (CGFloat, CGFloat) in [(-1, 0), (0, 1), (0, -1), (0, 0), (0.5, 1)] {
            let swipe = NavigationSwipeEvent(deltaX: x, deltaY: y, window: window)
            XCTAssertTrue(view.handle(swipe) === swipe)
        }
        XCTAssertEqual(backCount, 0)
        view.goBack = { false }
        let unavailable = NavigationSwipeEvent(deltaX: 1, deltaY: 0, window: window)
        XCTAssertTrue(view.handle(unavailable) === unavailable)
    }

    func testUnaddressedCoreGraphicsButtonTargetsKeyWindowOnly() throws {
        let (window, view) = makeWindow(isKeyWindow: true)
        let (otherWindow, otherView) = makeWindow()
        defer { close(otherWindow, otherView); close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }
        otherView.goBack = { XCTFail("An unaddressed click must not navigate another window"); return true }

        let cgDown = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown,
            mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: 3)!
        ))
        let down = try XCTUnwrap(NSEvent(cgEvent: cgDown))
        XCTAssertNil(down.window)
        XCTAssertEqual(down.buttonNumber, 3)
        XCTAssertTrue(otherView.handle(down) === down)
        NSApp.sendEvent(down)
        let cgUp = try XCTUnwrap(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseUp,
            mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: 3)!
        ))
        NSApp.sendEvent(try XCTUnwrap(NSEvent(cgEvent: cgUp)))
        XCTAssertEqual(backCount, 1)
        NSApp.sendEvent(NavigationSwipeEvent(deltaX: 1, deltaY: 0, window: nil))
        XCTAssertEqual(backCount, 2)
    }

    func testSwiftUIBackgroundInstallsMouseAndSwipeMonitor() async throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        var backCount = 0
        let content = Color.clear.background {
            MouseBackNavigation { backCount += 1; return true }
                .frame(width: 0, height: 0)
        }
        let hostingView = NSHostingView(rootView: content)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        // Let SwiftUI complete its representable's window attachment.
        try await Task.sleep(nanoseconds: 20_000_000)

        NSApp.sendEvent(MouseButtonEvent(.otherMouseDown, button: 3, window: window))
        NSApp.sendEvent(MouseButtonEvent(.otherMouseUp, button: 3, window: window))
        NSApp.sendEvent(NavigationSwipeEvent(deltaX: 1, deltaY: 0, window: window))
        XCTAssertEqual(backCount, 2)
    }

    func testOneBackPerClickAndBothEventsAreConsumed() {
        let (window, view) = makeWindow()
        defer { close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }

        XCTAssertNil(view.handle(MouseButtonEvent(.otherMouseDown, button: 3, window: window)))
        XCTAssertNil(view.handle(MouseButtonEvent(.otherMouseUp, button: 3, window: window)))
        XCTAssertEqual(backCount, 1)
    }

    func testMiddleForwardAndUnavailableBackPassThrough() {
        let (window, view) = makeWindow()
        defer { close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return false }

        for button in [0, 1, 2, 4] {
            let event = MouseButtonEvent(.otherMouseDown, button: button, window: window)
            XCTAssertTrue(view.handle(event) === event)
        }
        XCTAssertEqual(backCount, 0)
        let down = MouseButtonEvent(.otherMouseDown, button: 3, window: window)
        let up = MouseButtonEvent(.otherMouseUp, button: 3, window: window)
        XCTAssertTrue(view.handle(down) === down)
        XCTAssertTrue(view.handle(up) === up)
        XCTAssertEqual(backCount, 1)
    }

    func testOtherWindowsAndSheetsDoNotNavigateUnderlyingPage() {
        let (window, view) = makeWindow()
        let (otherWindow, otherView) = makeWindow()
        defer { close(otherWindow, otherView); close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }
        let otherEvent = MouseButtonEvent(.otherMouseDown, button: 3, window: otherWindow)
        XCTAssertTrue(view.handle(otherEvent) === otherEvent)

        window.beginSheet(otherWindow)
        let coveredEvent = MouseButtonEvent(.otherMouseDown, button: 3, window: window)
        XCTAssertTrue(view.handle(coveredEvent) === coveredEvent)
        let coveredSwipe = NavigationSwipeEvent(deltaX: 1, deltaY: 0, window: window)
        XCTAssertTrue(view.handle(coveredSwipe) === coveredSwipe)
        window.endSheet(otherWindow)
        XCTAssertEqual(backCount, 0)
    }

    func testWindowMonitorReceivesEventBeforeChildControlsAndStopsWhenDetached() {
        let (window, view) = makeWindow()
        defer { close(window, view) }
        var backCount = 0
        view.goBack = { backCount += 1; return true }

        NSApp.sendEvent(MouseButtonEvent(.otherMouseDown, button: 3, window: window))
        NSApp.sendEvent(MouseButtonEvent(.otherMouseUp, button: 3, window: window))
        XCTAssertEqual(backCount, 1)
        XCTAssertNil(view.hitTest(.zero), "The monitor must never intercept normal pointer hit testing")
        window.contentView = nil
        XCTAssertNil(view.window)
    }

    private func makeWindow(isKeyWindow: Bool = false) -> (NSWindow, MouseBackMonitorView) {
        _ = NSApplication.shared
        let window = NavigationTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.testIsKeyWindow = isKeyWindow
        window.isReleasedWhenClosed = false
        let view = MouseBackMonitorView()
        let content = NSView(frame: window.contentLayoutRect)
        content.addSubview(view)
        content.addSubview(NSButton(title: "Content control", target: nil, action: nil))
        window.contentView = content
        return (window, view)
    }

    private func close(_ window: NSWindow, _ view: MouseBackMonitorView) {
        view.stopMonitoring()
        window.contentView = nil
        window.close()
    }
}

private final class NavigationTestWindow: NSWindow {
    var testIsKeyWindow = false
    override var isKeyWindow: Bool { testIsKeyWindow }
}

private final class NavigationSwipeEvent: NSEvent {
    private let horizontal: CGFloat
    private let vertical: CGFloat
    private let targetWindow: NSWindow?

    init(deltaX: CGFloat, deltaY: CGFloat, window: NSWindow?) {
        horizontal = deltaX
        vertical = deltaY
        targetWindow = window
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used by tests") }
    override var type: NSEvent.EventType { .swipe }
    override var deltaX: CGFloat { horizontal }
    override var deltaY: CGFloat { vertical }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { targetWindow?.windowNumber ?? 0 }
}

/// NSEvent's public mouse factory does not accept an auxiliary button number.
private final class MouseButtonEvent: NSEvent {
    private let eventType: NSEvent.EventType
    private let number: Int
    private let targetWindow: NSWindow

    init(_ type: NSEvent.EventType, button: Int, window: NSWindow) {
        eventType = type
        number = button
        targetWindow = window
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used by tests") }
    override var type: NSEvent.EventType { eventType }
    override var buttonNumber: Int { number }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { targetWindow.windowNumber }
}
