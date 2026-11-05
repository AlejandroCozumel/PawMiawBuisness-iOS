//
//  VisitLocation.swift
//  PawMiawNegocios
//
//  Where the phone is at the two presses of a home visit — "I've arrived" and
//  "Finish" / "Leave" — on a visit the person started, and only when the
//  business turned it on (Ajustes de Domicilio, `locationStamps`; backend
//  docs/home-visits-late-and-notices.md, the web's lib/home-visits.ts). Never
//  in between: a walk's route is Services' walk tracker, not this.
//  Used by Domicilio (Services) and a home stay's visit, from Domicilio or the
//  stay (Stays). The app holds the when-in-use location permission; the first
//  press asks for it.
//

import CoreLocation
import Foundation

/// What the phone gave at a press: a place, or why there is none (the server's `PositionInput`).
struct VisitPosition: Codable, Equatable {
    let status: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    var accuracyM: Double? = nil
    var capturedAt: String? = nil

    var json: JSONValue {
        var object: [String: JSONValue] = ["status": .string(status)]
        if let latitude { object["latitude"] = .number(latitude) }
        if let longitude { object["longitude"] = .number(longitude) }
        if let accuracyM { object["accuracyM"] = .number(accuracyM) }
        if let capturedAt { object["capturedAt"] = .string(capturedAt) }
        return .object(object)
    }

    var body: [String: Any?] {
        var out: [String: Any?] = ["status": status]
        if let latitude { out["latitude"] = latitude }
        if let longitude { out["longitude"] = longitude }
        if let accuracyM { out["accuracyM"] = accuracyM }
        if let capturedAt { out["capturedAt"] = capturedAt }
        return out
    }
}

enum VisitLocation {
    private struct Settings: Decodable { let locationStamps: Bool? }

    /// Whether the business records the place at arrive and finish (read by everyone who works home visits or stays).
    static func stampsOn() async -> Bool {
        let settings: Settings? = try? await API.get("/provider-home-visits/settings")
        return settings?.locationStamps == true
    }

    /// The place of a press when the business records it (nil when it doesn't): asked at the press, 8 s at most.
    static func stamp(_ on: Bool) -> (() async -> VisitPosition)? {
        on ? { await VisitLocator.shared.position() } : nil
    }
}

/// Where the phone is right now, for the stamp of Arrive / Finish. It always answers — a position,
/// or why there is none — within 8 seconds of the permission being settled, and never throws.
final class VisitLocator: NSObject, CLLocationManagerDelegate {
    static let shared = VisitLocator()

    /// The longest Arrive or Finish waits for a position.
    static let timeout: TimeInterval = 8
    /// The server takes an accuracy up to this; a coarser fix is sent as this ("too imprecise" either way).
    private static let accuracyMax: Double = 100_000

    private let manager = CLLocationManager()
    private var fixWaiters: [(VisitPosition) -> Void] = []
    private var authorizationWaiters: [() -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func position() async -> VisitPosition {
        if manager.authorizationStatus == .notDetermined {
            // The first press asks for the permission; the 8 seconds start once it's answered (30 s at most).
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                var resumed = false
                let finish = { if !resumed { resumed = true; done.resume() } }
                authorizationWaiters.append(finish)
                manager.requestWhenInUseAuthorization()
                Task { try? await Task.sleep(for: .seconds(30)); finish() }
            }
        }
        switch manager.authorizationStatus {
        case .denied, .restricted: return VisitPosition(status: "denied")
        case .notDetermined: return VisitPosition(status: "timeout")
        default: break
        }
        return await withCheckedContinuation { (done: CheckedContinuation<VisitPosition, Never>) in
            var resumed = false
            let finish: (VisitPosition) -> Void = { answer in if !resumed { resumed = true; done.resume(returning: answer) } }
            fixWaiters.append(finish)
            manager.requestLocation()
            Task { try? await Task.sleep(for: .seconds(Self.timeout)); finish(VisitPosition(status: "timeout")) }
        }
    }

    private func answer(_ position: VisitPosition) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0(position) }
    }

    static func position(latitude: Double, longitude: Double, accuracy: Double, at: Date) -> VisitPosition {
        let measured = accuracy >= 0 ? accuracy : accuracyMax
        return VisitPosition(status: "ok", latitude: latitude, longitude: longitude,
                             accuracyM: min(accuracyMax, max(0, measured.rounded())), capturedAt: DateText.iso(at))
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard manager.authorizationStatus != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let valid = CLLocationCoordinate2DIsValid(last.coordinate)
        let latitude = last.coordinate.latitude, longitude = last.coordinate.longitude, accuracy = last.horizontalAccuracy, at = last.timestamp
        MainActor.assumeIsolated {
            answer(valid ? Self.position(latitude: latitude, longitude: longitude, accuracy: accuracy, at: at) : VisitPosition(status: "unavailable"))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { answer(VisitPosition(status: denied ? "denied" : "unavailable")) }
    }
}
