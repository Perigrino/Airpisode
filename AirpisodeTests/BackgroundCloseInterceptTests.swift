import XCTest
@testable import Airpisode

/// Exercises the runtime behaviour that GUI automation can't reach (System Events was
/// degraded during development): closing the window must hide, never destroy, and a reopen
/// must bring the same window back — that is the whole background-notification contract.
@MainActor
final class BackgroundCloseInterceptTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        return window
    }

    func testCloseHidesInsteadOfDestroyingAndReopenBringsItBack() throws {
        // No `defer { window.close() }` here: destroying the window at test end crashes
        // XCTest's lifetime scanner (SIGSEGV in the autorelease-pool audit), so the window is
        // simply left referenced by the interceptor's statics instead.
        let window = makeWindow()
        BackgroundCloseIntercept.install(on: window)
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.isVisible, "precondition: window on screen")

        let interceptor = try XCTUnwrap(window.delegate as? BackgroundCloseIntercept)
        // The veto is what keeps SwiftUI from destroying the window (and thereby the app):
        // a close request reads as a hide instead.
        XCTAssertFalse(interceptor.windowShouldClose(window))
        XCTAssertFalse(window.isVisible, "close reads as off-screen")
        XCTAssertNotNil(window.delegate, "window object must survive the close hide")

        // Dock click / reopen AppleEvent lands in the AppDelegate's reopen hook and the very
        // same window comes back on screen — no duplicate is ever created.
        XCTAssertTrue(BackgroundCloseIntercept.bringMainWindowBackIfNeeded())
        XCTAssertTrue(window.isVisible)
    }

    func testInstallIsIdempotent() {
        let window = makeWindow()
        BackgroundCloseIntercept.install(on: window)
        let first = window.delegate
        BackgroundCloseIntercept.install(on: window)
        XCTAssertTrue(window.delegate is BackgroundCloseIntercept)
        XCTAssertTrue(window.delegate === first, "install must never double-wrap the delegate")
    }
}
