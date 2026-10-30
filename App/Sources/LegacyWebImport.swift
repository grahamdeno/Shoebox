import Foundation
import WebKit

/// SPEC 11.2 step 3: when no backup file is found, read 1.0's saves straight from its web storage.
/// 1.0 kept them in the IndexedDB of https://inmyshoebox.com inside this same app container, so a hidden
/// web view on that origin can read them and hand back a version 2 backup. Nothing is written or deleted.
/// [Check] Must be tested on a phone that has 1.0 installed, online and offline.
@MainActor
final class LegacyWebImport: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var continuation: CheckedContinuation<Data?, Never>?

    /// True when this container has WebKit storage, which only 1.0 could have written.
    static var mightHaveOldSaves: Bool {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return false }
        return FileManager.default.fileExists(atPath: lib.appending(path: "WebKit").path())
    }

    func run() async -> Data? {
        await withCheckedContinuation { c in
            continuation = c
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.limitsNavigationsToAppBoundDomains = false
            let w = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: config)
            w.navigationDelegate = self
            web = w
            // A blank page on the old origin: same storage, none of the old app's code runs.
            w.loadHTMLString("<!doctype html><title>Shoebox</title>", baseURL: URL(string: "https://inmyshoebox.com/"))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish(nil)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.read() }
    }

    private func read() async {
        guard let web else { return finish(nil) }
        do {
            let value = try await web.callAsyncJavaScript(Self.script, contentWorld: .defaultClient)
            if let text = value as? String, let data = text.data(using: .utf8) { finish(data) } else { finish(nil) }
        } catch { finish(nil) }
    }

    private func finish(_ data: Data?) {
        guard let c = continuation else { return }
        continuation = nil
        web = nil
        c.resume(returning: data)
    }

    /// Reads the `edition` database and `edition.*` settings into `{app:"edition", version:2, ...}`.
    private static let script = """
    const open = () => new Promise((res, rej) => { const r = indexedDB.open("edition"); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); r.onupgradeneeded = () => { r.transaction.abort(); rej("none"); }; });
    const all = (db, name) => new Promise((res) => { if (!db.objectStoreNames.contains(name)) return res([]); const q = db.transaction(name, "readonly").objectStore(name).getAll(); q.onsuccess = () => res(q.result || []); q.onerror = () => res([]); });
    const b64 = async (blob) => { const bytes = new Uint8Array(await blob.arrayBuffer()); let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000)); return btoa(s); };
    let db; try { db = await open(); } catch (e) { return null; }
    const items = await all(db, "items"), meta = await all(db, "meta"), blobs = await all(db, "blobs");
    if (!items.length) return null;
    const files = [];
    for (const r of blobs) { if (r && r.blob) files.push({ id: r.id, type: r.blob.type || "", data: await b64(r.blob) }); }
    const settings = {};
    for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && k.startsWith("edition.")) settings[k] = localStorage.getItem(k); }
    return JSON.stringify({ app: "edition", version: 2, exported: new Date().toISOString(), items, meta, files, settings });
    """
}
