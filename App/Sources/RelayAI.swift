import Foundation
import DeviceCheck
import CryptoKit

/// Shoebox's AI on the relay (SPEC 9): App Attest proves this is the real app; the relay holds the key and the
/// cost limits. A 1.0 install's sign-up comes over with its backup, so it keeps working without a new one.
@MainActor
enum RelayAI {
    struct Failure: Error, LocalizedError { var message: String; var errorDescription: String? { message } }

    static var consented: Bool {
        guard let c = Prefs.load().aiConsent?.lowercased() else { return false }
        return !["", "0", "no", "false", "off"].contains(c)
    }

    /// Sends one Messages request and returns the text of the reply.
    static func ask(system: String, prompt: String, maxTokens: Int = 3500, model: String = "claude-haiku-5-5") async throws -> String {
        guard consented else { throw Failure(message: "AI is off.") }
        try await signUp()
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "system": system,
                                   "messages": [["role": "user", "content": prompt]]]
        let (data, status) = try await post("ai/messages", body, auth: true)
        if status == 401 || status == 403 {
            Prefs.update { $0.aiAttested = nil }
            try await signUp()
            let (d2, s2) = try await post("ai/messages", body, auth: true)
            return try text(d2, s2)
        }
        return try text(data, status)
    }

    private static func text(_ data: Data, _ status: Int) throws -> String {
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            throw Failure(message: ((o["error"] as? [String: Any])?["message"] as? String) ?? "Shoebox's AI didn't answer (\(status)).")
        }
        let parts = (o["content"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }

    /// Challenge from the relay, attested on the phone, checked by the relay. Keeps an existing sign-up's id.
    static func signUp() async throws {
        let p = Prefs.load()
        if p.aiDevice != nil, p.aiToken != nil, ["1", "true"].contains(p.aiAttested ?? "") { return }
        let service = DCAppAttestService.shared
        guard service.isSupported else { throw Failure(message: "This iPhone can't confirm Shoebox for AI.") }
        let (cd, cs) = try await post("ai/challenge", [:], auth: false)
        guard cs == 200, let challenge = ((try? JSONSerialization.jsonObject(with: cd)) as? [String: Any])?["challenge"] as? String,
              let raw = Data(base64Encoded: challenge) else { throw Failure(message: "Couldn't start AI.") }
        let keyId = try await service.generateKey()
        let attestation = try await service.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: raw)))
        let (ad, s) = try await post("ai/attest", ["challenge": challenge, "keyId": keyId, "attestation": attestation.base64EncodedString()], auth: true)
        guard s == 200, let o = (try? JSONSerialization.jsonObject(with: ad)) as? [String: Any],
              let device = o["device"] as? String, let token = o["token"] as? String else {
            throw Failure(message: "Couldn't confirm this copy of Shoebox. Try again later.")
        }
        Prefs.update { $0.aiDevice = device; $0.aiToken = token; $0.aiAttested = "1" }
    }

    private static func post(_ path: String, _ body: [String: Any], auth: Bool) async throws -> (Data, Int) {
        var req = URLRequest(url: Inbox.relay.appending(path: path))
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let p = Prefs.load()
        if auth, let d = p.aiDevice, let t = p.aiToken {
            req.setValue(d, forHTTPHeaderField: "x-shoebox-device")
            req.setValue(t, forHTTPHeaderField: "x-shoebox-token")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            return (data, (res as? HTTPURLResponse)?.statusCode ?? 0)
        } catch { throw Failure(message: "Couldn't reach Shoebox's AI. Check your connection.") }
    }

    /// The first JSON object in a reply.
    static func json(_ text: String) -> [String: Any] {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let o = try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8)) as? [String: Any] else { return [:] }
        return o
    }
}
