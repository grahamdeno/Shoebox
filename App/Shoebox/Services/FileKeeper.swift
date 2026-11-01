import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A file you picked, read and ready to keep.
struct PickedFile {
    var data: Data
    var name: String
    var type: UTType?
}

/// Keeps a file: the file itself so it can be opened again, its text so it can be searched, and a picture
/// of its first page (or the picture itself) to stand behind the post. Done on the phone.
enum FileKeeper {
    static let maxBytes = 25 * 1024 * 1024

    /// Reads a picked file's data, or nil with a reason when it is too big or can't be read.
    static func read(_ url: URL) -> (PickedFile?, String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxBytes else {
            return (nil, "That file is over 25 MB.")
        }
        guard let data = try? Data(contentsOf: url) else { return (nil, "That file couldn't be read.") }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return (PickedFile(data: data, name: url.lastPathComponent, type: type), nil)
    }

    static func save(_ file: PickedFile, note: String, now: Date = Date()) -> Save {
        let title = (file.name as NSString).deletingPathExtension
        let s = Save(title: title.isEmpty ? file.name : title, note: String(note.prefix(140)), origin: "a file", kind: .file, createdAt: now)
        s.fileData = file.data
        s.fileName = file.name
        s.fileType = file.type?.identifier
        s.enrichedAt = now

        if file.type?.conforms(to: .pdf) == true, let pdf = PDFDocument(data: file.data) {
            if let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                s.body = String(text.prefix(20_000))
                s.snippet = String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
            }
            if let page = pdf.page(at: 0) {
                let image = page.thumbnail(of: CGSize(width: 900, height: 1200), for: .mediaBox)
                s.imageData = image.jpegData(compressionQuality: 0.8)
                s.imageSource = "photo"
            }
        } else if file.type?.conforms(to: .image) == true {
            s.imageData = Relay.thumbnail(file.data, maxWidth: 1600) ?? file.data
            s.imageSource = "photo"
        } else if file.type?.conforms(to: .text) == true, let text = String(data: file.data, encoding: .utf8) {
            s.body = String(text.prefix(20_000))
            s.snippet = String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
        }
        Capture.place(s, note: note, now: now)
        return s
    }

    /// Writes the kept file to a temporary place so the system can show it.
    static func tempURL(for s: Save) -> URL? {
        guard let data = s.fileData else { return nil }
        let dir = FileManager.default.temporaryDirectory.appending(path: s.id.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: s.fileName ?? "file")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }
}
