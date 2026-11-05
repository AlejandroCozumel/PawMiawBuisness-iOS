//
//  SvcLocation.swift
//  PawMiawNegocios
//
//  A walk's route, on the phone that pressed Arrive and only when the business
//  turned it on (Ajustes de Domicilio; backend docs/home-visits-late-and-notices.md
//  and the web's hooks/use-walk-tracker.ts), while the app is open. Families
//  only ever see the route drawn as a line. The place at "I've arrived" and
//  "Finish" is Core/VisitLocation.swift.
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - Which walk this phone records

/// This phone pressed Arrive on this walk: it is the one that records (and the route waits here until sent).
enum SvcWalkTracking {
    private static func flag(_ appointmentId: String) -> String { "tracking.\(appointmentId)" }
    static func buffer(_ appointmentId: String) -> String { "route.v1.\(appointmentId)" }

    static func mark(_ appointmentId: String) {
        SvcDeviceStore.write(flag(appointmentId), Data(String(Date().timeIntervalSince1970).utf8))
    }

    static func isTracking(_ appointmentId: String) -> Bool { SvcDeviceStore.read(flag(appointmentId)) != nil }

    /// How long ago this phone pressed Arrive on the walk; nil when it didn't.
    static func age(_ appointmentId: String) -> TimeInterval? {
        guard let data = SvcDeviceStore.read(flag(appointmentId)) else { return nil }
        guard let since = Double(String(decoding: data, as: UTF8.self)), since > 0 else { return .infinity }
        return max(0, Date().timeIntervalSince1970 - since)
    }

    static func clear(_ appointmentId: String) {
        SvcDeviceStore.write(flag(appointmentId), nil)
        SvcDeviceStore.write(buffer(appointmentId), nil)
    }
}

/// One fix of a walk: the device's time (epoch ms), where, and how precise.
struct SvcWalkPoint: Codable, Equatable {
    let t: Double
    let lat: Double
    let lng: Double
    let acc: Double

    var json: JSONValue { .object(["t": .number(t), "lat": .number(lat), "lng": .number(lng), "acc": .number(acc)]) }

    static let accuracyMax: Double = 40
    static let minMeters: Double = 8
    static let minSeconds: Double = 20

    /// Kept when it is precise enough and the walker moved 8 m, or 20 s went by.
    static func keep(_ last: SvcWalkPoint?, _ fix: SvcWalkPoint) -> Bool {
        guard fix.acc.isFinite, fix.acc <= accuracyMax else { return false }
        guard let last else { return true }
        guard fix.t > last.t else { return false }
        let moved = CLLocation(latitude: last.lat, longitude: last.lng).distance(from: CLLocation(latitude: fix.lat, longitude: fix.lng))
        return moved >= minMeters || fix.t - last.t >= minSeconds * 1000
    }
}

// MARK: - A walk's route, recorded while the app is open

/// Records a walk's route between "I've arrived" and "Finish" on the phone that pressed Arrive — and only
/// there, only while the app is open and in front (it has no background location). Locking the phone or
/// leaving the app leaves a gap, drawn as a break. The screen is kept on while it records.
/// Kept fixes wait on the phone until they are handed to the outbox in batches (every 30 s or 30 points,
/// and once more right before Finish).
final class SvcWalkTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status { case off, recording, paused, unavailable }

    @Published private(set) var status: Status = .off
    /// Kept on this phone since the page was opened, sent or not.
    @Published private(set) var points = 0
    private(set) var appointmentId: String?
    private var itemId: String?
    private weak var outbox: SvcOutbox?

    private let manager = CLLocationManager()
    private var buffer: [SvcWalkPoint] = []
    private var last: SvcWalkPoint?
    private var lastBatchAt = Date()
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static let batchSize = 30
    private static let batchSeconds: TimeInterval = 30
    private static let bufferMax = 3000
    /// The server takes at most this many points in one call.
    private static let uploadMax = 200

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// The open walk this phone records (nil: none). Called as the day changes.
    func follow(appointmentId: String?, itemId: String?, outbox: SvcOutbox) {
        guard appointmentId != self.appointmentId else { return }
        stop()
        guard let appointmentId, let itemId else { return }
        self.appointmentId = appointmentId
        self.itemId = itemId
        self.outbox = outbox
        // A restart on this phone picks up what it had gathered.
        buffer = SvcDeviceStore.read(SvcWalkTracking.buffer(appointmentId)).flatMap { try? JSONDecoder().decode([SvcWalkPoint].self, from: $0) } ?? []
        last = buffer.last
        points = buffer.count
        lastBatchAt = Date()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            status = .unavailable
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default: break
        }
        status = UIApplication.shared.applicationState == .active ? .recording : .paused
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                if self.batchDue() { self.handOver() }
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status != .unavailable else { return }
                self.status = .paused
                self.handOver()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // "Paused" stays until the next position arrives, so the walker sees there was a gap.
                guard let self, self.appointmentId != nil else { return }
                UIApplication.shared.isIdleTimerDisabled = true
            }
        })
    }

    /// Hands what is left to the outbox and waits for it, never more than `timeout`.
    func flushNow(timeout: TimeInterval = 5) async {
        guard let itemId else { return }
        handOver()
        if let outbox { await outbox.settled(itemId: itemId, kind: "route_points", timeout: timeout) }
    }

    /// Hands what was gathered to the outbox now (a finish saved with no signal goes right after it).
    func handOverNow() { handOver() }

    func stop() {
        guard appointmentId != nil else { return }
        // What was gathered and not sent goes out with the finish (or is dropped by the server once the walk is closed).
        handOver()
        manager.stopUpdatingLocation()
        ticker?.cancel()
        ticker = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        UIApplication.shared.isIdleTimerDisabled = false
        appointmentId = nil
        itemId = nil
        buffer = []
        last = nil
        status = .off
        points = 0
    }

    private func batchDue() -> Bool {
        !buffer.isEmpty && (buffer.count >= Self.batchSize || Date().timeIntervalSince(lastBatchAt) >= Self.batchSeconds)
    }

    private func handOver() {
        guard let appointmentId, let itemId, let outbox, !buffer.isEmpty else { return }
        var start = 0
        while start < buffer.count {
            let batch = Array(buffer[start..<min(buffer.count, start + Self.uploadMax)])
            outbox.add(kind: "route_points", itemId: itemId, path: "/provider-appointments/\(appointmentId)/walk-route/points", body: ["points": .array(batch.map(\.json))])
            start += Self.uploadMax
        }
        // From here the outbox keeps them (and lets them go once the server has them).
        buffer = []
        SvcDeviceStore.write(SvcWalkTracking.buffer(appointmentId), nil)
        lastBatchAt = Date()
    }

    private func take(_ fix: SvcWalkPoint) {
        guard let appointmentId else { return }
        if UIApplication.shared.applicationState == .active { status = .recording }
        guard SvcWalkPoint.keep(last, fix) else { return }
        last = fix
        buffer.append(fix)
        if buffer.count > Self.bufferMax { buffer.removeFirst(buffer.count - Self.bufferMax) }
        SvcDeviceStore.write(SvcWalkTracking.buffer(appointmentId), try? JSONEncoder().encode(buffer))
        points += 1
        if batchDue() { handOver() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.filter { CLLocationCoordinate2DIsValid($0.coordinate) && $0.horizontalAccuracy >= 0 }.map {
            SvcWalkPoint(t: ($0.timestamp.timeIntervalSince1970 * 1000).rounded(), lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, acc: $0.horizontalAccuracy.rounded())
        }
        MainActor.assumeIsolated { fixes.forEach { take($0) } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Denied: nothing will come. Anything else may recover on its own.
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { if denied && appointmentId != nil { status = .unavailable } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard appointmentId != nil else { return }
            if status == .denied || status == .restricted { self.status = .unavailable }
        }
    }
}

/// What the phone is recording of the walk right now — said plainly, gaps included (web `RouteRecording`).
struct SvcRouteRecording: View {
    @ObservedObject var tracker: SvcWalkTracker

    var body: some View {
        switch tracker.status {
        case .off:
            EmptyView()
        case .unavailable:
            HStack(alignment: .top, spacing: 8) {
                Glyph("footprints", size: 16).padding(.top, 1)
                Text(L("The route couldn’t be recorded on this phone."))
            }
            .font(Theme.text(14, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        case .recording, .paused:
            let paused = tracker.status == .paused
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Glyph(paused ? "circle-pause" : "radio", size: 16).foregroundStyle(paused ? Theme.inkStrong : Theme.blue)
                    Text(paused ? L("Paused — the app was in the background") : LF("Recording route · %d points", tracker.points))
                }
                .font(Theme.text(14, weight: .heavy)).foregroundStyle(Theme.inkStrong)
                Text(L("Keep the app open and the screen on during the walk.")).font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wash(Theme.aqua, 12), in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.mix(Theme.aqua, 60, with: Theme.borderSoft), lineWidth: 1.5))
        }
    }
}

// MARK: - A walk's route as the family sees it

