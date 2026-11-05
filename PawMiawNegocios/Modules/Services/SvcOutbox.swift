//
//  SvcOutbox.swift
//  PawMiawNegocios
//
//  Domicilio without signal (web: hooks/use-home-visit-outbox.ts, the outbox
//  and "the day kept" in lib/home-visits.ts). Every Arrive, Finish, home-stay
//  arrival and leave, and a walk's route, is written to this phone first — so
//  the card flips at once and a dead zone loses nothing — then sent in the
//  order it was pressed, with the time it was pressed. Today's list as it last
//  loaded is kept too, to read the day with no signal. Both are kept per
//  business and person, emptied as the server takes each press, and dropped at
//  sign-out. The app sends while it is open (no background sending).
//

import Foundation
import Network
import SwiftUI
import UIKit

// MARK: - What this phone keeps (Application Support, never backed up loose)

enum SvcDeviceStore {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let url = base.appendingPathComponent("PawMiawNegocios/HomeVisits", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var copy = url
            try? copy.setResourceValues(values)
        }
        return url
    }

    private static func file(_ name: String) -> URL? {
        let safe = name.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }
        return folder?.appendingPathComponent(String(safe))
    }

    static func read(_ name: String) -> Data? {
        guard let url = file(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func write(_ name: String, _ data: Data?) {
        guard let url = file(name) else { return }
        if let data {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Every file this page leaves on a staff phone (sign-out).
    static func clearAll() {
        guard let url = folder else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Whether the phone has signal

@MainActor
final class SvcConnectivity: ObservableObject {
    static let shared = SvcConnectivity()

    @Published private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { @Sendable path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in SvcConnectivity.shared.update(satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "pawmiaw.negocios.connectivity"))
    }

    private func update(_ satisfied: Bool) {
        guard satisfied != online else { return }
        online = satisfied
        // With the signal back, a press doesn't sit out the wait its last failed try left it.
        if satisfied { SvcOutbox.wakeAll() }
    }
}

// MARK: - One press waiting to be sent

struct SvcOutboxEntry: Codable, Identifiable, Equatable {
    let id: String
    /// arrive, finish, stay_arrive, stay_leave, route_points.
    let kind: String
    /// The card it belongs to (`a_…` / `s_…`).
    let itemId: String
    let path: String
    var body: [String: JSONValue]
    /// When the button was pressed: what the server stamps.
    let pressedAt: String
    /// locating, queued, sending, failed.
    var state: String
    var attempts: Int
    /// Not before this moment (the wait after a failed try).
    var nextAt: Date?
    var error: String?
    var errorCode: String?

    var isPress: Bool { kind != "route_points" }
}

/// A card's unsent press: it waits for its position, it is saved, or it is on its way.
enum SvcPending: Equatable {
    case locating, saved, sending

    /// Only the seconds a press takes to get its position or its answer hold the card's next button:
    /// a walk that starts and ends in a dead zone is still finished on time.
    var holdsNextPress: Bool { self != .saved }
}

@MainActor
final class SvcOutbox: ObservableObject {
    /// A press older than this isn't tried again on its own.
    static let maxAge: TimeInterval = 12 * 3600

    @Published private(set) var entries: [SvcOutboxEntry]
    private let key: String?
    private var flushing = false
    private var timer: Task<Void, Never>?

    private static var stores: [String: SvcOutbox] = [:]
    private static var watchingSignOut = false

    private init(key: String?) {
        self.key = key
        if let key, let data = SvcDeviceStore.read(key), let saved = try? JSONDecoder().decode([SvcOutboxEntry].self, from: data) {
            entries = Self.recover(saved)
        } else {
            entries = []
        }
    }

    /// One queue per business and person, shared by everything that reads it.
    static func store(clinicId: String?, userId: String?) -> SvcOutbox {
        watchSignOut()
        guard let clinicId, let userId else {
            if let loose = stores["none"] { return loose }
            let loose = SvcOutbox(key: nil)
            stores["none"] = loose
            return loose
        }
        let key = "outbox.v1.\(clinicId).\(userId)"
        if let found = stores[key] { return found }
        let store = SvcOutbox(key: key)
        stores[key] = store
        store.flushSoon()
        return store
    }

    static func wakeAll() { for store in stores.values { store.wake() } }
    static func flushAll() { for store in stores.values { store.flushSoon() } }

    /// The session ended: whatever this page kept on the phone goes with it.
    private static func watchSignOut() {
        guard !watchingSignOut else { return }
        watchingSignOut = true
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            guard UserDefaults.standard.object(forKey: "pawmiaw_negocios_user") == nil else { return }
            Task { @MainActor in
                guard !SvcOutbox.stores.isEmpty else { return }
                SvcOutbox.stores.removeAll()
                SvcDeviceStore.clearAll()
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in SvcOutbox.flushAll() }
        }
    }

    // MARK: Reading

    /// Presses on this phone not yet with the server (route batches aren't presses).
    var waiting: [SvcOutboxEntry] { entries.filter { $0.isPress && $0.state != "failed" } }
    var failed: [SvcOutboxEntry] { entries.filter { $0.isPress && $0.state == "failed" } }

    var pending: [String: SvcPending] {
        var out: [String: SvcPending] = [:]
        for entry in waiting {
            out[entry.itemId] = entry.state == "locating" ? .locating : entry.state == "sending" ? .sending : .saved
        }
        return out
    }

    /// The day as the person left it: a press not sent yet already shows on its card at the time it was pressed.
    /// A failed press shows nothing — the card is as the server has it.
    func apply(_ items: [SvcHomeVisitItem]) -> [SvcHomeVisitItem] {
        let presses = waiting
        guard !presses.isEmpty else { return items }
        return items.map { item in
            var next = item
            for entry in presses where entry.itemId == item.id {
                if ["arrive", "stay_arrive"].contains(entry.kind) && ["upcoming", "on_my_way"].contains(next.phase) {
                    next.phase = "in_progress"
                    next.arrivedAt = entry.pressedAt
                    next.late = false
                    next.lateMinutes = 0
                    next.actions = SvcHomeActions(onMyWay: false, arrive: false, finish: true, reassign: false)
                } else if ["finish", "stay_leave"].contains(entry.kind) && next.phase == "in_progress" {
                    next.phase = "done"
                    next.finishedAt = entry.pressedAt
                    next.runningLong = false
                    next.actions = SvcHomeActions(onMyWay: next.actions?.onMyWay, arrive: next.actions?.arrive, finish: false, reassign: next.actions?.reassign)
                }
            }
            return next
        }
    }

    // MARK: Writing

    /// A press: written first, sent after. With `position` it waits for it (8 s at most — the locator's own limit).
    func add(kind: String, itemId: String, path: String, body: [String: JSONValue] = [:], pressedAt: Date = Date(), position: (() async -> VisitPosition)? = nil) {
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
        let at = DateText.iso(pressedAt)
        var payload = body
        // The press time is the visit's time, however late it is sent.
        if kind != "route_points" { payload["at"] = .string(at) }
        let entry = SvcOutboxEntry(id: id, kind: kind, itemId: itemId, path: path, body: payload, pressedAt: at,
                                   state: position == nil ? "queued" : "locating", attempts: 0)
        set(entries + [entry])
        if let position {
            Task {
                let answer = await position()
                self.set(self.entries.map { current in
                    guard current.id == id, current.state == "locating" else { return current }
                    var located = current
                    located.state = "queued"
                    located.body["position"] = answer.json
                    return located
                })
                self.flushSoon()
            }
        } else {
            flushSoon()
        }
    }

    func retry(_ id: String) {
        set(entries.map { entry in
            guard entry.id == id else { return entry }
            var again = entry
            again.state = "queued"
            again.nextAt = nil
            again.error = nil
            again.errorCode = nil
            return again
        })
        flushSoon()
    }

    /// "Discard": the press is forgotten, with whatever of the same visit was waiting behind it.
    func discard(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = entries[index]
        set(entries.enumerated().filter { offset, entry in
            entry.id != id && !(entry.itemId == target.itemId && offset > index && entry.isPress)
        }.map(\.element))
    }

    /// The press was settled another way (the start gate sent it): only that entry goes.
    func resolve(_ id: String) {
        set(entries.filter { $0.id != id })
        flushSoon()
    }

    /// The signal is back: whatever was waiting out a failed try may go now.
    func wake() {
        set(entries.map { entry in
            guard entry.state == "queued", entry.nextAt != nil else { return entry }
            var now = entry
            now.nextAt = nil
            return now
        })
        flushSoon()
    }

    /// Resolves when nothing of this visit's kind is waiting any more, or after `timeout`.
    func settled(itemId: String, kind: String, timeout: TimeInterval) async {
        let limit = Date().addingTimeInterval(timeout)
        while Date() < limit {
            if !entries.contains(where: { $0.itemId == itemId && $0.kind == kind && $0.state != "failed" }) { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // MARK: Sending

    func flushSoon() { Task { await flush() } }

    /// Sends what may go now, one at a time, in the order pressed; a visit's failed press holds the rest of it.
    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer {
            flushing = false
            schedule()
        }
        while let entry = nextToSend(Date()) {
            set(entries.map { $0.id == entry.id ? Self.with($0, state: "sending") : $0 })
            let outcome = await send(entry)
            settle(entry.id, outcome)
        }
    }

    private enum Outcome { case sent, retry, failed(String?, String?) }

    private func nextToSend(_ now: Date) -> SvcOutboxEntry? {
        var seen = Set<String>()
        for entry in entries {
            if seen.contains(entry.itemId) { continue }
            seen.insert(entry.itemId)
            if entry.state == "queued" && (entry.nextAt ?? .distantPast) <= now { return entry }
        }
        return nil
    }

    private func send(_ entry: SvcOutboxEntry) async -> Outcome {
        let fresh = Date().timeIntervalSince(DateText.parse(entry.pressedAt) ?? Date()) < Self.maxAge
        do {
            let data = try JSONEncoder().encode(entry.body)
            _ = try await API.data("POST", entry.path, query: [:], body: data)
            if entry.isPress { announceDataChanged() }
            return .sent
        } catch let error as APIError {
            // A stay visit already arrived (or already left) is done.
            if entry.kind == "stay_arrive" && error.status == 409 && error.code == "visit_closed" { announceDataChanged(); return .sent }
            if entry.kind == "stay_leave" && error.status == 409 && error.code == "visit_not_started" { announceDataChanged(); return .sent }
            let transient = error.isOffline || error.status >= 500 || error.status == 408 || error.status == 429
            if transient { return fresh ? .retry : .failed(L("It was pressed more than 12 hours ago"), nil) }
            // A route batch the server won't take (the walk closed, routes off): nobody can act on it.
            if !entry.isPress { return .sent }
            return .failed(error.message, error.code)
        } catch is CancellationError {
            return .retry
        } catch {
            return fresh ? .retry : .failed(nil, nil)
        }
    }

    private func settle(_ id: String, _ outcome: Outcome) {
        set(entries.compactMap { entry in
            guard entry.id == id else { return entry }
            var next = entry
            next.attempts += 1
            switch outcome {
            case .sent:
                return nil
            case .retry:
                next.state = "queued"
                // 2 s, 4 s, 8 s … up to a minute.
                next.nextAt = Date().addingTimeInterval(min(60, 2 * pow(2, Double(max(0, next.attempts - 1)))))
            case .failed(let message, let code):
                next.state = "failed"
                next.nextAt = nil
                next.error = message
                next.errorCode = code
            }
            return next
        })
    }

    /// Never later than 20 s: a signal that came back unnoticed is still found.
    private func schedule() {
        timer?.cancel()
        let waits = entries.filter { $0.state == "queued" }.map { $0.nextAt ?? .distantPast }
        guard let soonest = waits.min() else { return }
        let delay = min(20, max(0.25, soonest.timeIntervalSinceNow))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func set(_ next: [SvcOutboxEntry]) {
        entries = next
        guard let key else { return }
        SvcDeviceStore.write(key, next.isEmpty ? nil : try? JSONEncoder().encode(next))
    }

    private static func with(_ entry: SvcOutboxEntry, state: String) -> SvcOutboxEntry {
        var copy = entry
        copy.state = state
        return copy
    }

    /// What a restart finds: a press still waiting for its position goes without one; one caught mid-send is sent again.
    private static func recover(_ saved: [SvcOutboxEntry]) -> [SvcOutboxEntry] {
        saved.map { entry in
            var next = entry
            if entry.state == "locating" {
                next.state = "queued"
                next.body["position"] = VisitPosition(status: "timeout").json
            } else if entry.state == "sending" {
                next.state = "queued"
            }
            return next
        }
    }

    /// Why a press could not be saved, in the reader's language.
    static func reason(_ entry: SvcOutboxEntry) -> String {
        if let code = entry.errorCode, let sentence = SvcRefusals.homeVisits[code] ?? SvcRefusals.common[code] { return L(sentence) }
        if let message = entry.error?.nonEmpty { return message }
        if Date().timeIntervalSince(DateText.parse(entry.pressedAt) ?? Date()) >= maxAge { return L("It was pressed more than 12 hours ago") }
        return L("Something went wrong. Try again.")
    }
}

// MARK: - The day kept for when the signal drops

struct SvcCachedDay: Codable {
    let savedAt: String
    let day: SvcHomeVisitsDay
}

enum SvcDayCache {
    private static func key(_ clinicId: String, _ userId: String) -> String { "day.v1.\(clinicId).\(userId)" }

    /// Only today is kept, and only the list as the server sent it (it carries no access values).
    static func save(_ day: SvcHomeVisitsDay, clinicId: String?, userId: String?) {
        guard day.isToday == true, let clinicId, let userId else { return }
        SvcDeviceStore.write(key(clinicId, userId), try? JSONEncoder().encode(SvcCachedDay(savedAt: DateText.iso(Date()), day: day)))
    }

    /// A kept day is shown only while it is still its day.
    static func read(clinicId: String?, userId: String?) -> SvcCachedDay? {
        guard let clinicId, let userId, let data = SvcDeviceStore.read(key(clinicId, userId)),
              let kept = try? JSONDecoder().decode(SvcCachedDay.self, from: data) else { return nil }
        let today = DateText.dayKey(Date(), zone: SvcTime.zone(kept.day.timeZone))
        return kept.day.date == today ? kept : nil
    }
}

// MARK: - What the card says about its presses

/// A press on this phone not yet with the server: said quietly, on its card (web `PendingLine`).
struct SvcPendingLine: View {
    let pending: SvcPending

    var body: some View {
        HStack(spacing: 8) {
            if pending == .saved {
                Glyph("cloud-off", size: 16)
            } else {
                ProgressView().controlSize(.small).tint(Theme.inkStrong)
            }
            Text(pending == .saved ? L("Saved · will send when there’s signal") : pending == .locating ? L("Getting your location…") : L("Sending…"))
        }
        .font(Theme.text(14, weight: .bold))
        .foregroundStyle(Theme.inkStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.mango, 20), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
    }
}

/// A press the server refused (web `OutboxRow`): what it said, and what can be done — try again,
/// forget it, or (a missing consent, a deposit) settle that first. The card is back to how the server has it.
struct SvcOutboxRow: View {
    let entry: SvcOutboxEntry
    let onRetry: () -> Void
    let onDiscard: () -> Void
    var onOpenVisit: (() -> Void)? = nil
    var onReviewConsents: (() -> Void)? = nil

    private var gate: Bool { entry.errorCode == "consent_required" || entry.errorCode == "deposit_required" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Glyph("triangle-alert", size: 16).foregroundStyle(Theme.destructive).padding(.top, 2)
                Text(LF("Couldn’t be saved: %@", SvcOutbox.reason(entry)))
                    .font(Theme.text(14, weight: .bold)).foregroundStyle(Theme.inkStrong)
            }
            FlowLayout(spacing: 8) {
                if gate, let onReviewConsents {
                    PMButton(L("Review consents"), systemImage: "signature", action: onReviewConsents)
                } else {
                    PMButton(L("Try again"), systemImage: "rotate-cw", action: onRetry)
                }
                if gate, let onOpenVisit {
                    PMButton(L("Open visit"), systemImage: "external-link", variant: .outline, action: onOpenVisit)
                }
                PMButton(L("Discard"), systemImage: "trash-2", variant: .outline, action: onDiscard)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.destructive, 8), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.destructive, 45, with: Theme.borderSoft), lineWidth: 1.5))
    }
}

/// Said at the top of the list when the phone has no signal or presses are still waiting (web `OfflineBanner`).
struct SvcOfflineBanner: View {
    let online: Bool
    let waiting: Int
    let failed: Int
    /// The time of the list shown from this phone's copy; nil when it is live.
    let cachedAt: String?

    var body: some View {
        if !online || waiting > 0 || failed > 0 || cachedAt != nil {
            let offline = !online || cachedAt != nil
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 8) {
                    HStack(spacing: 8) {
                        if offline { Glyph("cloud-off", size: 16) }
                        else if failed > 0 && waiting == 0 { Glyph("triangle-alert", size: 16) }
                        else { ProgressView().controlSize(.small).tint(Theme.inkStrong) }
                        Text(cachedAt.map { LF("Offline · showing what was loaded at %@", $0) }
                             ?? (offline ? L("You’re offline") : waiting > 0 ? L("Sending…") : LF("%d couldn’t be saved", failed)))
                    }
                    .font(Theme.text(14, weight: .heavy))
                    if waiting > 0 { pill(LF("%d waiting to send", waiting)) }
                    if failed > 0 && (offline || waiting > 0) { pill(LF("%d couldn’t be saved", failed)) }
                }
                if offline {
                    Text(L("The app keeps working without signal: arrivals and finishes are saved and sent when the signal is back. Keep the app open until they go."))
                        .font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkStrong.opacity(0.78))
                }
            }
            .foregroundStyle(Theme.inkStrong)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.mango, 22), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.mango, 70, with: Theme.borderSoft), lineWidth: 1.5))
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.brandText(12, weight: .heavy)).monospacedDigit()
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Theme.surface, in: Capsule())
    }
}
