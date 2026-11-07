import XCTest

/// The UX audit's recorder (docs/audit/08-ux-audit.md). Each journey walks the real app in the simulator the way a
/// person would, takes a picture at every step, checks what should be on screen, runs Apple's accessibility audit on
/// the screens that matter, and writes it all to AUDIT_OUT/<config>/<journey>/ for the review.
///
/// A check that does not hold is written down as a finding and the walk goes on, so one run shows every problem.
@MainActor
final class Audit {
    static let env = ProcessInfo.processInfo.environment
    static let config = env["AUDIT_CONFIG"] ?? "local"
    static let root = URL(fileURLWithPath: env["AUDIT_OUT"] ?? NSTemporaryDirectory() + "audit").appending(path: config)

    let journey: String
    let app = XCUIApplication()
    private let dir: URL
    private var n = 0
    private var steps: [[String: Any]] = []
    private var issues: [[String: Any]] = []
    private let started = Date()
    private var last = Date()

    init(_ journey: String) {
        self.journey = journey
        dir = Audit.root.appending(path: journey)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Starts the app with the sample data and this run's text size and colors.
    func launch(_ args: [String] = [], terminate: Bool = true) {
        if terminate { app.terminate() }
        var a = ["-demo", "YES"] + args
        if let c = Audit.env["AUDIT_COLORS"], !c.isEmpty { a += ["-colors", c] }
        if let t = Audit.env["AUDIT_TEXT"], !t.isEmpty { a += ["-UIPreferredContentSizeCategoryName", t] }
        app.launchArguments = a
        app.launch()
        pause(2.5)
    }

    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    // MARK: Recording

    /// A picture of the screen as it is now, numbered in walk order.
    @discardableResult
    func shot(_ name: String, note: String = "") -> String {
        n += 1
        let file = String(format: "%02d-%@.png", n, name.replacingOccurrences(of: " ", with: "-"))
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appending(path: file))
        let now = Date()
        steps.append(["n": n, "kind": "shot", "name": name, "file": file, "note": note,
                      "t": round(now.timeIntervalSince(started) * 10) / 10, "dt": round(now.timeIntervalSince(last) * 100) / 100])
        last = now
        return file
    }

    /// A check: written down either way. Severity 1 (cosmetic) to 4 (blocks the task) when it fails.
    @discardableResult
    func check(_ name: String, _ ok: Bool, severity: Int = 3, detail: String = "") -> Bool {
        steps.append(["n": n, "kind": "check", "name": name, "ok": ok, "severity": ok ? 0 : severity, "detail": detail])
        return ok
    }

    /// Waits for an element and checks it is there.
    @discardableResult
    func expect(_ name: String, _ e: XCUIElement, timeout: Double = 4, severity: Int = 3) -> Bool {
        check(name, e.waitForExistence(timeout: timeout), severity: severity, detail: e.debugDescription.prefix(200).description)
    }

    /// How long a move took to settle, in seconds, for the record.
    func timing(_ name: String, _ seconds: Double) {
        steps.append(["n": n, "kind": "timing", "name": name, "seconds": round(seconds * 100) / 100])
    }

    /// Apple's accessibility audit on the screen as it is now: contrast, labels, hit areas, clipped text, Dynamic Type.
    /// Every issue is written down; none stops the walk.
    func accessibility(_ screen: String) {
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                var label = ""
                if let e = issue.element, e.exists { label = e.label.isEmpty ? e.identifier : e.label }
                self.issues.append(["screen": screen, "type": Audit.typeName(issue.auditType), "summary": issue.compactDescription,
                                    "detail": issue.detailedDescription, "element": label])
                return true
            }
        } catch {
            issues.append(["screen": screen, "type": "auditError", "summary": "\(error)", "detail": "", "element": ""])
        }
    }

    static func typeName(_ t: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamicType"), (.textClipped, "textClipped"),
            (.trait, "trait"),
        ]
        return names.first { t.contains($0.0) }?.1 ?? "other(\(t.rawValue))"
    }

    /// What is on screen, as a person using VoiceOver would meet it: the labels of the buttons and words, top to bottom.
    /// Read from one snapshot of the tree: element-by-element queries go stale while the screen moves.
    func labels(_ name: String) {
        guard let snap = try? app.snapshot() else {
            steps.append(["n": n, "kind": "labels", "name": name, "buttons": [String](), "texts": ["(no snapshot)"]])
            return
        }
        var buttons: [String] = []
        var texts: [String] = []
        func walk(_ s: XCUIElementSnapshot) {
            if s.elementType == .button, !s.label.isEmpty { buttons.append(s.label) }
            if s.elementType == .staticText, !s.label.isEmpty { texts.append(s.label) }
            for c in s.children { walk(c) }
        }
        walk(snap)
        steps.append(["n": n, "kind": "labels", "name": name, "buttons": Array(buttons.prefix(40)), "texts": Array(texts.prefix(60))])
    }

    /// Anything on screen (a word, a button, a field) whose label holds the words.
    func any(containing s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    /// Writes the record. Call at the end of every journey.
    func finish() {
        let doc: [String: Any] = ["journey": journey, "config": Audit.config, "steps": steps, "accessibility": issues,
                                  "seconds": round(Date().timeIntervalSince(started))]
        if let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appending(path: "record.json"))
        }
    }

    // MARK: Moves

    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// A tap on the post, the way a thumb opens it.
    func tapPost() { point(0.5, 0.4).tap() }

    /// Flick up: past 100 pt, quick.
    func flickUp() { point(0.5, 0.62).press(forDuration: 0.02, thenDragTo: point(0.5, 0.3), withVelocity: .fast, thenHoldForDuration: 0) }

    /// Pull down: past 160 pt, held a moment, let go over the box.
    func pullDown() { point(0.5, 0.35).press(forDuration: 0.05, thenDragTo: point(0.5, 0.72), withVelocity: .default, thenHoldForDuration: 0.15) }

    /// Pull the Shoebox sheet up from the box.
    func pullBoxUp() { point(0.5, 0.95).press(forDuration: 0.02, thenDragTo: point(0.5, 0.3)) }

    /// The first element whose label starts with the words.
    func button(startingWith s: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", s)).firstMatch
    }

    func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
    }

    /// A text field (one line or many) by its label or its placeholder, trying each name in turn.
    func field(_ names: String...) -> XCUIElement {
        for s in names {
            let byID = app.descendants(matching: .any).matching(identifier: s).firstMatch
            if byID.exists { return byID }
            for q in [app.textFields, app.textViews] {
                let p = q.matching(NSPredicate(format: "label == %@ OR identifier == %@ OR placeholderValue == %@", s, s, s)).firstMatch
                if p.exists { return p }
            }
        }
        return app.textFields[names.first ?? ""]
    }

    /// Taps a word if it is there; written down as a finding if not.
    @discardableResult
    func tap(_ name: String, _ e: XCUIElement, severity: Int = 3, timeout: Double = 4) -> Bool {
        guard expect("can tap \(name)", e, timeout: timeout, severity: severity) else { return false }
        if e.isHittable { e.tap() } else { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        return true
    }

    /// The "x of y" counter at the top of Today, or nil.
    var counter: String? {
        let e = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ of [0-9]+$")).firstMatch
        return e.exists ? e.label : nil
    }

    /// The count on the box ("Your Shoebox, 9" reads 9).
    var boxCount: Int? {
        let e = button(startingWith: "Your Shoebox")
        guard e.exists else { return nil }
        return Int(e.label.components(separatedBy: ", ").last ?? "")
    }
}
