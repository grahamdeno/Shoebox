import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI
import ShoeboxCore

/// The Daily Issue opened (long press): the cover, then each line with its own answers (SPEC 6).
/// Also the expanded single moment: your reason large, with its picture.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func didReceive(_ notification: UNNotification) {
        let info = notification.request.content.userInfo
        let ids: [UUID]
        if let list = info["issue"] as? [String] { ids = list.compactMap(UUID.init(uuidString:)) }
        else if let one = (info["saveId"] as? String).flatMap(UUID.init(uuidString:)) { ids = [one] }
        else { ids = [] }
        let isIssue = info["issue"] != nil
        let root = AnyView(IssueView(ids: ids, isIssue: isIssue, date: notification.date).themed())
        if let host { host.rootView = root; return }
        let h = UIHostingController(rootView: root)
        h.sizingOptions = .preferredContentSize
        h.view.backgroundColor = .clear
        addChild(h)
        view.addSubview(h.view)
        h.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            h.view.topAnchor.constraint(equalTo: view.topAnchor),
            h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        h.didMove(toParent: self)
        host = h
        preferredContentSize = h.view.intrinsicContentSize
    }
}

struct IssueView: View {
    let ids: [UUID]
    let isIssue: Bool
    let date: Date
    @Environment(\.roles) private var roles
    @State private var answered: [UUID: String] = [:]

    var body: some View {
        let keeper = Keeper.shared()
        let saves = ids.compactMap { keeper.save(id: $0) }.filter { $0.deletedAt == nil }
        VStack(alignment: .leading, spacing: Metric.space3) {
            HStack(spacing: Metric.space2) {
                AppMark()
                Text(isIssue ? "Today's Issue · " + date.formatted(.dateTime.weekday(.wide)) : "Shoebox").type(.meta).foregroundStyle(roles.quiet)
            }
            ForEach(Array(saves.enumerated()), id: \.element.id) { i, s in
                VStack(alignment: .leading, spacing: Metric.space2) {
                    if i > 0 { Hairline() }
                    if !isIssue, let pic = keeper.picture(for: s), let img = UIImage(contentsOfFile: pic.path()) {
                        Image(uiImage: img).resizable().scaledToFill().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: Metric.radiusPicture))
                    }
                    Text(s.headline).type(i == 0 ? .reasonLg : .reasonMd).foregroundStyle(roles.text).fixedSize(horizontal: false, vertical: true)
                    if !s.reason.isEmpty { Text([s.title, s.host].compactMap { $0 }.joined(separator: " · ")).type(.label).foregroundStyle(roles.quiet).lineLimit(1) }
                    if let a = answered[s.id] {
                        Text(a).type(.label).foregroundStyle(roles.done)
                    } else if isIssue {
                        HStack(spacing: Metric.space2) {
                            Button(Engine.doneWord(s)) { keeper.done(s, surface: "issue"); answered[s.id] = "Done"; reschedule(keeper) }
                                .buttonStyle(i == 0 ? AnyButtonStyle(ActButtonStyle()) : AnyButtonStyle(LineButtonStyle()))
                            Button(keeper.nextMoment(for: s)?.laterLabel ?? "Later") {
                                let p = keeper.later(s, Engine.laterChoice(for: keeper.nextMoment(for: s)?.laterLabel), events: CalendarReader.upcoming(), surface: "issue")
                                answered[s.id] = p.explanation; reschedule(keeper)
                            }.buttonStyle(LineButtonStyle())
                            Button("Drop") { keeper.drop(s, surface: "issue"); answered[s.id] = "Dropped"; reschedule(keeper) }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(Metric.space4)
    }

    private func reschedule(_ k: Keeper) { Task { await Engine.schedule(k); WidgetsBridge.reload() } }
}

/// One act-colored button per view: only the first line's main answer gets it.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
