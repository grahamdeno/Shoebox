import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A file you picked, read and ready to keep: its bytes, plus the text and picture worked out once, off the
/// main thread, so Keep is instant.
struct PickedFile: Sendable {
    var data: Data
    var name: String
    var type: UTType?
    var text = ""
    var picture: Data?
}

/// Keeps a file: the file itself so it can be opened again, its text so it can be searched, and a picture
/// of its first page (or the picture itself) to stand behind the post. Done on the phone.
enum FileKeeper {
    static let maxBytes = 25 * 1024 * 1024
    /// Enough text to search and read dates from, without reading a whole book.
    static let maxPages = 20

    /// Reads a picked file off the main thread, or gives a reason it couldn't.
    static func read(_ url: URL) async -> (PickedFile?, String?) {
        await Task.detached(priority: .userInitiated) { readNow(url) }.value
    }

    nonisolated static func readNow(_ url: URL) -> (PickedFile?, String?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Some places don't know the size until the file is downloaded; check it again after reading.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            return (nil, "That file is over 25 MB.")
        }
        guard let data = coordinatedRead(url) else { return (nil, "That file couldn't be read. If it's in iCloud, open it once in Files first.") }
        guard data.count <= maxBytes else { return (nil, "That file is over 25 MB.") }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        var file = PickedFile(data: data, name: safeName(url.lastPathComponent), type: type)
        prepare(&file)
        return (file, nil)
    }

    /// Waits for iCloud to bring the file down, then reads it.
    nonisolated private static func coordinatedRead(_ url: URL) -> Data? {
        var data: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { data = try? Data(contentsOf: $0) }
        return data ?? (try? Data(contentsOf: url))
    }

    nonisolated private static func prepare(_ file: inout PickedFile) {
        if file.type?.conforms(to: .pdf) == true, let pdf = PDFDocument(data: file.data) {
            var parts: [String] = []
            var count = 0
            for i in 0..<min(pdf.pageCount, maxPages) {
                guard let t = pdf.page(at: i)?.string, !t.isEmpty else { continue }
                parts.append(t)
                count += t.count
                if count > 20_000 { break }
            }
            file.text = String(parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).prefix(20_000))
            if let page = pdf.page(at: 0) {
                file.picture = page.thumbnail(of: CGSize(width: 900, height: 1200), for: .mediaBox).jpegData(compressionQuality: 0.8)
            }
        } else if file.type?.conforms(to: .image) == true {
            file.picture = Relay.thumbnail(file.data, maxWidth: 1600)
        } else if file.type?.conforms(to: .text) == true, let text = String(data: file.data, encoding: .utf8) {
            file.text = String(text.prefix(20_000))
        }
    }

    static func save(_ file: PickedFile, note: String, now: Date = Date()) -> Save {
        let title = (file.name as NSString).deletingPathExtension
        let s = Save(title: title.isEmpty ? file.name : title, note: String(note.prefix(140)), origin: "a file", kind: .file, createdAt: now)
        s.fileData = file.data
        s.fileName = file.name
        s.fileType = file.type?.identifier
        s.enrichedAt = now
        if !file.text.isEmpty {
            s.body = file.text
            s.snippet = String(file.text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
        }
        if let picture = file.picture {
            s.imageData = picture
            s.imageSource = "photo"
        } else if file.type?.conforms(to: .image) == true {
            s.imageData = file.data
            s.imageSource = "photo"
        }
        Capture.place(s, note: note, now: now)
        return s
    }

    /// A plain file name: no folders, never empty.
    nonisolated static func safeName(_ name: String?) -> String {
        let n = ((name ?? "") as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty || n == "." || n == ".." ? "file" : n
    }

    /// Writes the kept file to a temporary place so the system can show it. `cleanUp` removes it after.
    static func tempURL(for s: Save) -> URL? {
        guard let data = s.fileData else { return nil }
        let dir = FileManager.default.temporaryDirectory.appending(path: "open-\(s.id.uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: safeName(s.fileName))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    static func cleanUp(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
