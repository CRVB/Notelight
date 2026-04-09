import Foundation
import Combine
import AppKit

struct MediaAttachment: Identifiable, Hashable {
    let id: UUID
    var fileURL: URL
    var createdAt: Date
}

struct NoteItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var richContentData: Data?
    var mediaAttachments: [MediaAttachment]
    var createdAt: Date
    var updatedAt: Date

    var preview: String {
        content.replacingOccurrences(of: "\n", with: " ")
    }
}

final class AppState: ObservableObject {
    @Published var notes: [NoteItem] = [
        NoteItem(
            id: UUID(),
            title: "NoteLight'e hoş geldin",
            content: "Hızlı paneli açmak için Cmd+ç kullan.",
            richContentData: nil,
            mediaAttachments: [],
            createdAt: .now,
            updatedAt: .now
        ),
        NoteItem(
            id: UUID(),
            title: "Örnek not",
            content: "Bu uygulamayı sadeleştirilmiş bir akışla kullanıyoruz.",
            richContentData: nil,
            mediaAttachments: [],
            createdAt: .now.addingTimeInterval(-3600),
            updatedAt: .now.addingTimeInterval(-3600)
        )
    ]
    @Published var selectedNoteID: UUID?

    var selectedNote: NoteItem? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    func selectFirstIfNeeded() {
        if selectedNoteID == nil {
            selectedNoteID = notes.first?.id
        }
    }

    func addQuickNote(text: String, richContentData: Data? = nil, mediaAttachments: [MediaAttachment] = []) {
        let title = text.split(separator: "\n").first.map(String.init) ?? "Yeni Not"
        let item = NoteItem(
            id: UUID(),
            title: title,
            content: text,
            richContentData: richContentData,
            mediaAttachments: mediaAttachments,
            createdAt: .now,
            updatedAt: .now
        )
        notes.insert(item, at: 0)
        selectedNoteID = item.id
    }

    func createNewNote() {
        let item = NoteItem(
            id: UUID(),
            title: "Yeni Not",
            content: "",
            richContentData: nil,
            mediaAttachments: [],
            createdAt: .now,
            updatedAt: .now
        )
        notes.insert(item, at: 0)
        selectedNoteID = item.id
    }

    func updateSelectedNote(title: String, attributedContent: NSAttributedString, mediaAttachments: [MediaAttachment]) {
        guard let selectedNoteID else { return }
        guard let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        notes[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Başlıksız Not" : title
        notes[index].content = attributedContent.string
        notes[index].richContentData = attributedContent.rtfdData()
        notes[index].mediaAttachments = mediaAttachments
        notes[index].updatedAt = .now
    }

    func deleteSelectedNote() {
        guard let selectedNoteID else { return }
        guard let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        notes.remove(at: index)
        self.selectedNoteID = notes.first?.id
    }
}

extension NSAttributedString {
    func rtfdData() -> Data? {
        let fullRange = NSRange(location: 0, length: length)
        return try? data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
    }

    static func fromStoredContent(data: Data?, plainText: String) -> NSAttributedString {
        if let data,
           let attributed = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil
           ) {
            return attributed
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        return NSAttributedString(string: plainText, attributes: attrs)
    }
}
