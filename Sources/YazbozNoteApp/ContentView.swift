import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var editorTitle = ""
    @State private var editorAttributedContent = NSAttributedString(string: "")
    @State private var editorMediaAttachments: [MediaAttachment] = []
    @State private var syncingEditor = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var filteredNotes: [NoteItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return appState.notes }
        return appState.notes.filter {
            $0.title.localizedCaseInsensitiveContains(needle) ||
            $0.content.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Notlarda ara...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)

                List(selection: $appState.selectedNoteID) {
                    ForEach(filteredNotes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(note.preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(dateFormatter.string(from: note.updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .tag(note.id)
                    }
                }
                .listStyle(.inset)
            }
            .navigationTitle("Notlar")
        } detail: {
            if appState.selectedNote != nil {
                NoteEditorView(
                    title: $editorTitle,
                    attributedContent: $editorAttributedContent,
                    mediaAttachments: $editorMediaAttachments,
                    onSave: {
                        appState.updateSelectedNote(
                            title: editorTitle,
                            attributedContent: editorAttributedContent,
                            mediaAttachments: editorMediaAttachments
                        )
                    }
                )
                .id(appState.selectedNoteID)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                ContentUnavailableView("Not Seçilmedi", systemImage: "note.text")
            }
        }

        .toolbar {
            ToolbarItemGroup {
                Button {
                    appState.createNewNote()
                    syncEditorFromSelection()
                } label: {
                    Label("Yeni Not", systemImage: "plus")
                }

                Button(role: .destructive) {
                    appState.deleteSelectedNote()
                    syncEditorFromSelection()
                } label: {
                    Label("Sil", systemImage: "trash")
                }
                .disabled(appState.selectedNote == nil)

                Button {
                    NotificationCenter.default.post(name: .toggleQuickCapturePanel, object: nil)
                } label: {
                    Label("Hızlı Yakala", systemImage: "bolt.fill")
                }
            }
        }
        .onAppear {
            appState.selectFirstIfNeeded()
            syncEditorFromSelection()
        }
        .onChange(of: appState.selectedNoteID) { _, _ in
            syncEditorFromSelection()
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: appState.selectedNoteID)
        .animation(.easeInOut(duration: 0.2), value: appState.notes)
    }

    private func syncEditorFromSelection() {
        guard let note = appState.selectedNote else {
            syncingEditor = true
            editorTitle = ""
            editorAttributedContent = NSAttributedString(string: "")
            syncingEditor = false
            return
        }
        syncingEditor = true
        editorTitle = note.title
        editorAttributedContent = NSAttributedString.fromStoredContent(
            data: note.richContentData,
            plainText: note.content
        )
        editorMediaAttachments = note.mediaAttachments
        syncingEditor = false
    }

}

private struct NoteEditorView: View {
    @Binding var title: String
    @Binding var attributedContent: NSAttributedString
    @Binding var mediaAttachments: [MediaAttachment]
    let onSave: () -> Void
    @State private var showSavedMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Başlık", text: $title)
                .font(.system(size: 28, weight: .bold))
                .textFieldStyle(.plain)
            Divider()
            RichTextEditorView(attributedText: $attributedContent)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.quaternary, lineWidth: 1)
                )

            Spacer()
            HStack {
                if showSavedMessage {
                    Label("Kaydedildi", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
                Button("Kaydet") {
                    onSave()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showSavedMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showSavedMessage = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

private struct RichTextEditorView: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    private static let originalAttachmentSizeKey = NSAttributedString.Key("NoteLightOriginalAttachmentSize")

    private final class FitAttachmentTextView: NSTextView {
        var onSizeChanged: (() -> Void)?
        private var lastNotifiedWidth: CGFloat = 0

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if let textContainer {
                textContainer.containerSize = NSSize(width: max(0, newSize.width), height: .greatestFiniteMagnitude)
            }
            if abs(newSize.width - lastNotifiedWidth) > 0.5 {
                lastNotifiedWidth = newSize.width
                onSizeChanged?()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = FitAttachmentTextView()
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFontPanel = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: max(0, scrollView.contentSize.width),
            height: .greatestFiniteMagnitude
        )
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)
        textView.onSizeChanged = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.scaleAttachmentsToFit(in: textView)
        }
        context.coordinator.scaleAttachmentsToFit(in: textView)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

        func updateNSView(_ nsView: NSScrollView, context: Context) {
            guard let textView = context.coordinator.textView else { return }
            if !textView.attributedString().isEqual(to: attributedText) {
                textView.textStorage?.setAttributedString(attributedText)
            }
            if context.coordinator.hasAttachments(in: textView) {
                DispatchQueue.main.async {
                    context.coordinator.scaleAttachmentsToFit(in: textView)
                }
            }
        }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var attributedText: NSAttributedString
        weak var textView: NSTextView?
        private var isScaling = false
        private var lastUsableWidth: CGFloat = 0

        init(attributedText: Binding<NSAttributedString>) {
            _attributedText = attributedText
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if hasAttachments(in: textView) {
                scaleAttachmentsToFit(in: textView)
            }
            attributedText = textView.attributedString()
        }

        func hasAttachments(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage else { return false }
            let fullRange = NSRange(location: 0, length: storage.length)
            var found = false
            storage.enumerateAttribute(.attachment, in: fullRange, options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
                if value is NSTextAttachment {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        func scaleAttachmentsToFit(in textView: NSTextView) {
            if isScaling { return }
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let containerWidth = textView.textContainer?.size.width ?? textView.bounds.width
            let usableWidth = max(120, containerWidth - (textView.textContainerInset.width * 2) - 12)

            if abs(usableWidth - lastUsableWidth) < 0.5 { return }

            isScaling = true
            defer {
                lastUsableWidth = usableWidth
                isScaling = false
            }

            storage.beginEditing()
            storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
                guard let attachment = value as? NSTextAttachment else { return }

                let originalSize: NSSize
                if let stored = storage.attribute(
                    RichTextEditorView.originalAttachmentSizeKey,
                    at: range.location,
                    effectiveRange: nil
                ) as? NSValue {
                    originalSize = stored.sizeValue
                } else {
                    let inferred = attachment.image?.size
                    let current = attachment.bounds.size
                    let sourceSize = inferred ?? current
                    originalSize = NSSize(
                        width: max(sourceSize.width, 1),
                        height: max(sourceSize.height, 1)
                    )
                    storage.addAttribute(
                        RichTextEditorView.originalAttachmentSizeKey,
                        value: NSValue(size: originalSize),
                        range: range
                    )
                }

                let targetWidth = min(originalSize.width, usableWidth)
                let ratio = targetWidth / originalSize.width
                let targetHeight = max(1, originalSize.height * ratio)
                let currentSize = attachment.bounds.size
                if abs(currentSize.width - targetWidth) > 0.5 || abs(currentSize.height - targetHeight) > 0.5 {
                    attachment.bounds = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
                }
            }
            storage.endEditing()
        }
    }
}
