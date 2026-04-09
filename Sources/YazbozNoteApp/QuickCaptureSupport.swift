import AppKit
import QuartzCore

struct QuickCaptureSubmissionRequest: Equatable {
    let wantsScreenshot: Bool
    let wantsLink: Bool
    let normalizedText: String?

    init(input: String) {
        wantsScreenshot = input.contains("\"\"")
        wantsLink = input.contains("-link")

        let cleaned = input
            .replacingOccurrences(of: "\"\"", with: "")
            .replacingOccurrences(of: "-link", with: "")
        normalizedText = QuickCaptureInputCoordinator.normalizeSubmission(cleaned)
    }

    var shouldSubmit: Bool {
        wantsScreenshot || wantsLink || normalizedText != nil
    }
}

struct BrowserLinkContext {
    let bundleID: String
    let processID: pid_t
    let icon: NSImage?
}

class BrowserLinkResolver {
    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    func resolve(context: BrowserLinkContext?) -> String? {
        guard let context else { return nil }

        if let direct = resolveDirectURL(from: context), isValidURL(direct) {
            return direct
        }

        if let addressBar = captureURLViaAddressBar(from: context), isValidURL(addressBar) {
            return addressBar
        }

        return nil
    }

    func resolveDirectURL(from context: BrowserLinkContext) -> String? {
        guard let script = Self.directBrowserURLScript(for: context.bundleID),
              let value = executeAppleScript(script),
              isValidURL(value) else {
            return nil
        }

        return value
    }

    func captureURLViaAddressBar(from context: BrowserLinkContext) -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard()
        let originalString = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentApp = NSRunningApplication.current

        defer {
            restorePasteboard(snapshot)
            _ = currentApp.activate(options: [.activateAllWindows])
        }

        guard let app = NSRunningApplication(processIdentifier: context.processID) else { return nil }
        _ = app.activate(options: [.activateAllWindows])
        Thread.sleep(forTimeInterval: 0.14)

        let changeCount = pasteboard.changeCount
        let script = """
        tell application "System Events"
            keystroke "l" using command down
            delay 0.08
            keystroke "c" using command down
        end tell
        """
        _ = executeAppleScript(script)

        let timeout = CFAbsoluteTimeGetCurrent() + 0.7
        var didChangeClipboard = false
        while CFAbsoluteTimeGetCurrent() < timeout {
            if pasteboard.changeCount != changeCount {
                didChangeClipboard = true
            }

            if let candidate = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               isValidURL(candidate),
               didChangeClipboard || candidate != originalString {
                return candidate
            }

            Thread.sleep(forTimeInterval: 0.04)
        }

        if let candidate = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           isValidURL(candidate),
           didChangeClipboard || candidate != originalString {
            return candidate
        }

        return nil
    }

    func isValidURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return false
        }

        if value.lowercased() == "about:blank" {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    static func isSupportedBrowser(bundleID: String) -> Bool {
        directBrowserURLScript(for: bundleID) != nil
    }

    static func directBrowserURLScript(for bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return (URL of current tab of front window as text)
            end tell
            """
        case "com.google.Chrome":
            return chromiumURLScript(for: "Google Chrome")
        case "company.thebrowser.Browser":
            return chromiumURLScript(for: "Arc")
        case "com.brave.Browser":
            return chromiumURLScript(for: "Brave Browser")
        case "com.microsoft.edgemac":
            return chromiumURLScript(for: "Microsoft Edge")
        default:
            return nil
        }
    }

    private static func chromiumURLScript(for applicationName: String) -> String {
        """
        tell application "\(applicationName)"
            if (count of windows) is 0 then return ""
            return (URL of active tab of front window as text)
        end tell
        """
    }

    private func snapshotPasteboard() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let serialized: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var mapped: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    mapped[type] = data
                }
            }
            return mapped
        } ?? []

        return PasteboardSnapshot(items: serialized)
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for itemMap in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in itemMap {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    private func executeAppleScript(_ script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }

        var errorInfo: NSDictionary?
        let output = appleScript.executeAndReturnError(&errorInfo)
        if errorInfo != nil { return nil }

        let value = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

protocol QuickCaptureToasting: AnyObject {
    func show(message: String, anchoredTo window: NSWindow)
}

final class QuickCaptureToastController: QuickCaptureToasting {
    private let panel: QuickCaptureToastWindow
    private let contentView = QuickCaptureToastView(frame: .zero)
    private var hideWorkItem: DispatchWorkItem?

    init() {
        panel = QuickCaptureToastWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.isFloatingPanel = true
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .mainMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = contentView
    }

    func show(message: String, anchoredTo window: NSWindow) {
        hideWorkItem?.cancel()
        contentView.message = message

        let targetSize = preferredSize(for: message)
        let anchorFrame = window.frame
        let targetFrame = NSRect(
            x: anchorFrame.midX - (targetSize.width / 2),
            y: anchorFrame.minY - targetSize.height - 10,
            width: targetSize.width,
            height: targetSize.height
        )

        panel.setFrame(targetFrame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.90, 0.30, 1.00)
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideAnimated()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.94, execute: workItem)
    }

    private func hideAnimated() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.40, 0.00, 0.60, 0.20)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func preferredSize(for message: String) -> NSSize {
        let maxWidth: CGFloat = 320
        let textInsets = NSSize(width: 32, height: 16)
        let textFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textBounds = NSAttributedString(
            string: message,
            attributes: [.font: textFont]
        ).boundingRect(
            with: NSSize(width: maxWidth - textInsets.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let width = min(maxWidth, max(180, ceil(textBounds.width) + textInsets.width))
        let height = max(38, ceil(textBounds.height) + textInsets.height)
        return NSSize(width: width, height: height)
    }
}

private final class QuickCaptureToastWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class QuickCaptureToastView: NSView {
    private let label = NSTextField(labelWithString: "")

    var message: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

func widthAdjustedFrame(_ frame: NSRect, width: CGFloat) -> NSRect {
    NSRect(
        x: frame.midX - (width / 2),
        y: frame.origin.y,
        width: width,
        height: frame.height
    )
}
