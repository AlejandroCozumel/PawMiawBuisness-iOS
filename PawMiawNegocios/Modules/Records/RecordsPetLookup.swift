//
//  RecordsPetLookup.swift
//  PawMiawNegocios
//
//  Whose a pet is and what it is called, from its provider client pet id
//  alone. The backend has no route that reads one pet, so the pet's own
//  lists say it: its records, visits and follow-ups carry its client and its
//  name, its chart summary its client, and the client its pets. Only what the
//  reader's role can read answers; the rest is skipped. (A backend route
//  returning one pet with its client would replace all of this.)
//

import Foundation

enum RecordsPetLookup {
    struct Found: Equatable {
        var clientId: String?
        var petName: String?
    }

    static func find(_ petId: String) async -> Found {
        var found = Found()
        let probes: [(String, [String: String?])] = [
            ("/provider-records", ["limit": "1", "offset": "0", "providerClientPetId": petId]),
            ("/provider-appointments", ["limit": "1", "offset": "0", "providerClientPetId": petId]),
            ("/provider-follow-ups", ["limit": "1", "offset": "0", "status": "all", "providerClientPetId": petId]),
            ("/provider-client-pets/\(petId)/chart-summary", [:]),
        ]
        for (path, query) in probes {
            guard let value: JSONValue = try? await API.get(path, query: query) else { continue }
            scan(value, petId: petId, into: &found)
            if found.clientId != nil { break }
        }
        if found.clientId == nil {
            // Last: the patients list, a page at a time (the pet may be new, with nothing written yet).
            outer: for archived in [false, true] {
                var offset = 0
                while offset < 500 {
                    guard let page: JSONValue = try? await API.get("/provider-patients", query: ["limit": "50", "offset": "\(offset)", "archived": archived ? "true" : nil]) else { break }
                    let items = page["items"]?.array ?? []
                    if let row = items.first(where: { $0["id"]?.string == petId }) {
                        found.clientId = row["client"]?["id"]?.string ?? row["providerClientId"]?.string
                        if found.petName == nil { found.petName = row["petName"]?.string?.nonEmpty }
                        break outer
                    }
                    if items.count < 50 { break }
                    offset += 50
                }
            }
        }
        if let clientId = found.clientId, found.petName == nil, let client = try? await RecordsAPI.client(clientId) {
            found.petName = client.pets?.first { $0.id == petId }?.petName?.nonEmpty
        }
        return found
    }

    /// The first object naming this pet gives its client and, when it has it, its name.
    private static func scan(_ value: JSONValue, petId: String, into found: inout Found) {
        switch value {
        case .object(let object):
            if object["providerClientPetId"]?.string == petId {
                if found.clientId == nil { found.clientId = object["providerClientId"]?.string?.nonEmpty }
                if found.petName == nil { found.petName = object["petName"]?.string?.nonEmpty }
            }
            for child in object.values where found.clientId == nil || found.petName == nil {
                scan(child, petId: petId, into: &found)
            }
        case .array(let items):
            for child in items where found.clientId == nil || found.petName == nil {
                scan(child, petId: petId, into: &found)
            }
        default:
            break
        }
    }
}
