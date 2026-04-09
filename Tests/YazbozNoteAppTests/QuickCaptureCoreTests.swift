import XCTest
import AppKit
@testable import YazbozNoteApp

private final class StubBrowserLinkResolver: BrowserLinkResolver {
    var directResult: String?
    var addressBarResult: String?
    private(set) var directCallCount = 0
    private(set) var addressBarCallCount = 0

    init(directResult: String? = nil, addressBarResult: String? = nil) {
        self.directResult = directResult
        self.addressBarResult = addressBarResult
    }

    override func resolveDirectURL(from context: BrowserLinkContext) -> String? {
        directCallCount += 1
        return directResult
    }

    override func captureURLViaAddressBar(from context: BrowserLinkContext) -> String? {
        addressBarCallCount += 1
        return addressBarResult
    }
}

private final class ToastSpy: QuickCaptureToasting {
    private(set) var messages: [String] = []

    func show(message: String, anchoredTo window: NSWindow) {
        messages.append(message)
    }
}

final class QuickCaptureCoreTests: XCTestCase {
    func testHotkeyPolicyPrefersLayoutKey() {
        let selected = QuickCaptureHotkeyPolicy.choosePrimaryKeyCode(
            layoutKeyCode: 47,
            fallbackKeyCodes: [41]
        )

        XCTAssertEqual(selected, 47)
    }

    func testHotkeyPolicyFallsBackWhenLayoutMissing() {
        let selected = QuickCaptureHotkeyPolicy.choosePrimaryKeyCode(
            layoutKeyCode: nil,
            fallbackKeyCodes: [41]
        )

        XCTAssertEqual(selected, 41)
    }

    func testStateMachineFlow() {
        var machine = QuickCapturePanelStateMachine()

        XCTAssertEqual(machine.state, .hidden)
        XCTAssertTrue(machine.requestShow())
        XCTAssertEqual(machine.state, .showing)

        machine.markVisible()
        XCTAssertEqual(machine.state, .visible)

        XCTAssertTrue(machine.requestHide())
        XCTAssertEqual(machine.state, .hiding)

        machine.markHidden()
        XCTAssertEqual(machine.state, .hidden)
    }

    func testStateMachineRejectsDuplicateShowAndHide() {
        var machine = QuickCapturePanelStateMachine()

        XCTAssertTrue(machine.requestShow())
        XCTAssertFalse(machine.requestShow())

        machine.markVisible()
        XCTAssertTrue(machine.requestHide())
        XCTAssertFalse(machine.requestHide())
    }

    func testNormalizeSubmissionRejectsWhitespaceOnly() {
        XCTAssertNil(QuickCaptureInputCoordinator.normalizeSubmission("   \n  "))
    }

    func testNormalizeSubmissionTrimsAndReturnsText() {
        XCTAssertEqual(
            QuickCaptureInputCoordinator.normalizeSubmission("  Merhaba dunya  \n"),
            "Merhaba dunya"
        )
    }

    func testSubmissionRequestParsesLinkOnly() {
        let request = QuickCaptureSubmissionRequest(input: "   -link   ")

        XCTAssertTrue(request.wantsLink)
        XCTAssertFalse(request.wantsScreenshot)
        XCTAssertNil(request.normalizedText)
        XCTAssertTrue(request.shouldSubmit)
    }

    func testSubmissionRequestParsesTextAndLink() {
        let request = QuickCaptureSubmissionRequest(input: "  not metni -link ")

        XCTAssertTrue(request.wantsLink)
        XCTAssertFalse(request.wantsScreenshot)
        XCTAssertEqual(request.normalizedText, "not metni")
    }

    func testSubmissionRequestParsesTextScreenshotAndLink() {
        let request = QuickCaptureSubmissionRequest(input: " metin \"\" -link ")

        XCTAssertTrue(request.wantsLink)
        XCTAssertTrue(request.wantsScreenshot)
        XCTAssertEqual(request.normalizedText, "metin")
    }

    func testSubmissionRequestParsesCommandOnlyWhitespacePayload() {
        let request = QuickCaptureSubmissionRequest(input: "  \"\"   -link  ")

        XCTAssertTrue(request.wantsLink)
        XCTAssertTrue(request.wantsScreenshot)
        XCTAssertNil(request.normalizedText)
        XCTAssertTrue(request.shouldSubmit)
    }

    func testBrowserLinkResolverUsesDirectSafariURLWithoutFallback() {
        let resolver = StubBrowserLinkResolver(
            directResult: "https://example.com/safari",
            addressBarResult: "https://example.com/fallback"
        )
        let context = BrowserLinkContext(bundleID: "com.apple.Safari", processID: 1, icon: nil)

        XCTAssertEqual(resolver.resolve(context: context), "https://example.com/safari")
        XCTAssertEqual(resolver.directCallCount, 1)
        XCTAssertEqual(resolver.addressBarCallCount, 0)
    }

    func testBrowserLinkResolverUsesDirectChromiumURLWithoutFallback() {
        let resolver = StubBrowserLinkResolver(
            directResult: "https://example.com/chrome",
            addressBarResult: "https://example.com/fallback"
        )
        let context = BrowserLinkContext(bundleID: "com.google.Chrome", processID: 1, icon: nil)

        XCTAssertEqual(resolver.resolve(context: context), "https://example.com/chrome")
        XCTAssertEqual(resolver.directCallCount, 1)
        XCTAssertEqual(resolver.addressBarCallCount, 0)
    }

    func testBrowserLinkResolverFallsBackToAddressBarWhenDirectFails() {
        let resolver = StubBrowserLinkResolver(
            directResult: nil,
            addressBarResult: "https://example.com/fallback"
        )
        let context = BrowserLinkContext(bundleID: "com.brave.Browser", processID: 1, icon: nil)

        XCTAssertEqual(resolver.resolve(context: context), "https://example.com/fallback")
        XCTAssertEqual(resolver.directCallCount, 1)
        XCTAssertEqual(resolver.addressBarCallCount, 1)
    }

    func testBrowserLinkResolverReturnsNilWhenAllStrategiesFail() {
        let resolver = StubBrowserLinkResolver(
            directResult: "about:blank",
            addressBarResult: "notaurl"
        )
        let context = BrowserLinkContext(bundleID: "com.microsoft.edgemac", processID: 1, icon: nil)

        XCTAssertNil(resolver.resolve(context: context))
        XCTAssertEqual(resolver.directCallCount, 1)
        XCTAssertEqual(resolver.addressBarCallCount, 1)
    }

    func testWidthAdjustedFramePreservesCenterAndHeight() {
        let targetFrame = NSRect(x: 120, y: 340, width: 700, height: 62)
        let adjustedFrame = widthAdjustedFrame(targetFrame, width: 780)

        XCTAssertEqual(adjustedFrame.width, 780, accuracy: 0.001)
        XCTAssertEqual(adjustedFrame.height, targetFrame.height, accuracy: 0.001)
        XCTAssertEqual(adjustedFrame.midX, targetFrame.midX, accuracy: 0.001)
        XCTAssertEqual(adjustedFrame.origin.y, targetFrame.origin.y, accuracy: 0.001)
    }
}

@MainActor
final class QuickCaptureIntegrationTests: XCTestCase {
    func testControllerShowSetsVisibleAndSingleWindow() {
        _ = NSApplication.shared
        let appState = AppState()
        let controller = QuickCaptureWindowController(appState: appState)

        controller.show(animated: false)
        XCTAssertEqual(controller.visibilityState, .visible)

        let firstWindow = controller.debugWindow
        controller.toggle(animated: false)
        XCTAssertEqual(controller.visibilityState, .hidden)

        controller.toggle(animated: false)
        XCTAssertEqual(controller.visibilityState, .visible)
        XCTAssertTrue(firstWindow === controller.debugWindow)

        controller.hide(reason: .toggle, animated: false)
        XCTAssertEqual(controller.visibilityState, .hidden)
    }

    func testControllerFocusesInputAfterShow() {
        _ = NSApplication.shared
        let appState = AppState()
        let controller = QuickCaptureWindowController(appState: appState)

        controller.show(animated: false)

        let expectation = expectation(description: "input focus acquired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if controller.debugWindow.firstResponder === controller.debugInputField ||
                controller.debugWindow.firstResponder === controller.debugInputField.currentEditor() {
                expectation.fulfill()
                return
            }

            XCTFail("Input field did not become first responder")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        controller.hide(reason: .toggle, animated: false)
    }

    func testEscapePathHidesPanel() {
        _ = NSApplication.shared
        let appState = AppState()
        let controller = QuickCaptureWindowController(appState: appState)

        controller.show(animated: false)
        XCTAssertEqual(controller.visibilityState, .visible)

        controller.debugHandleEscape()
        XCTAssertEqual(controller.visibilityState, .hidden)
    }

    func testSubmitPathAddsNoteAndHidesPanel() {
        _ = NSApplication.shared
        let appState = AppState()
        let initialCount = appState.notes.count
        let controller = QuickCaptureWindowController(appState: appState)

        controller.show(animated: false)
        controller.debugSubmitForTests("  Test notu  ")

        XCTAssertEqual(appState.notes.count, initialCount + 1)
        XCTAssertEqual(appState.notes.first?.content, "Test notu")
        XCTAssertEqual(controller.visibilityState, .hidden)
    }

    func testLinkSubmitAddsNoteAndHidesPanelWhenResolverSucceeds() {
        _ = NSApplication.shared
        let appState = AppState()
        let initialCount = appState.notes.count
        let resolver = StubBrowserLinkResolver(directResult: "https://example.com")
        let toastSpy = ToastSpy()
        let controller = QuickCaptureWindowController(
            appState: appState,
            linkResolver: resolver,
            toastPresenter: toastSpy
        )

        controller.show(animated: false)
        controller.debugSetBrowserContextForTests(
            BrowserLinkContext(bundleID: "com.google.Chrome", processID: 1, icon: nil)
        )
        controller.debugSubmitForTests("Linkli not -link")

        XCTAssertEqual(appState.notes.count, initialCount + 1)
        XCTAssertEqual(appState.notes.first?.content, "Linkli not\nlink: https://example.com")
        XCTAssertEqual(controller.visibilityState, .hidden)
        XCTAssertTrue(toastSpy.messages.isEmpty)
    }

    func testLinkSubmitKeepsPanelVisibleWhenResolverFails() {
        _ = NSApplication.shared
        let appState = AppState()
        let initialCount = appState.notes.count
        let resolver = StubBrowserLinkResolver()
        let toastSpy = ToastSpy()
        let controller = QuickCaptureWindowController(
            appState: appState,
            linkResolver: resolver,
            toastPresenter: toastSpy
        )

        controller.show(animated: false)
        controller.debugSetBrowserContextForTests(
            BrowserLinkContext(bundleID: "com.google.Chrome", processID: 1, icon: nil)
        )
        controller.debugSubmitForTests("Link denemesi -link")

        XCTAssertEqual(appState.notes.count, initialCount)
        XCTAssertEqual(controller.visibilityState, .visible)
        XCTAssertEqual(controller.debugInputText, "Link denemesi -link")
        XCTAssertEqual(toastSpy.messages, ["Aktif sekme linki alinamadi"])
    }
}
