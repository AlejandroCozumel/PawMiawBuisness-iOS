//
//  RecordsNewRecordScreen.swift
//  PawMiawNegocios
//
//  A record written from the screen that asks for it (a pet's chart, a visit,
//  a follow-up's paperwork: ProviderRoute.newRecord). It is the record sheet
//  (RecordsRecordSheet) with what that screen knows already chosen, as the web
//  opens it there: a client and its pet skip "Client + pet", a type skips
//  "Record type", a visit is saved with the record and lends its client, pet
//  and the person it is with. Pushed rather than presented; Cancel and saving
//  go back, and the save is announced to every screen.
//

import SwiftUI

/// What a visit says about the record written at it.
private struct RecordsVisitContext: Decodable {
    let providerClientId: String?
    let providerClientPetId: String?
    let assignedMember: RecordsMemberRef?
}

struct NewRecordScreen: View {
    let prefill: RecordPrefill

    @EnvironmentObject private var workspace: Workspace
    @State private var context: RecordsSheetContext?
    @State private var members: [RecordsMember] = []

    private var access: RecordsAccess { RecordsAccess(workspace) }

    var body: some View {
        Group {
            if !access.writeRecords {
                PageScroll { NoAccessState(message: L("Ask the workspace owner to let your role write records.")) }
                    .providerPage(L("New record"))
            } else if let context {
                RecordsRecordSheet(context: context, members: members, access: access)
                    // The sheet opened as a page: its header is the top, no bar, no back swipe.
                    .environment(\.modalAsPage, true)
                    .navigationBarBackButtonHidden(true)
            } else {
                PageScroll { LoadingState() }
                    .providerPage(L("New record"))
            }
        }
        .task {
            guard context == nil, access.writeRecords else { return }
            await prepare()
        }
    }

    /// Reads what the hand-off left out: the visit's client, pet and person, the pet's client, and the team.
    private func prepare() async {
        let clinic = workspace.current?.clinicId
        var next = RecordsSheetContext(
            clientId: prefill.clientId?.nonEmpty,
            petId: prefill.petId?.nonEmpty,
            appointmentId: prefill.appointmentId?.nonEmpty,
            kind: RecordsSheetContext.kind(prefill.recordType)
        )
        let team = recordsStart(clinic != nil) { try await RecordsAPI.members(clinicId: clinic ?? "") }
        if let visitId = next.appointmentId {
            let path = "/provider-appointments/\(visitId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? visitId)"
            if let visit: RecordsVisitContext = try? await API.get(path) {
                if next.clientId == nil { next.clientId = visit.providerClientId?.nonEmpty }
                if next.petId == nil { next.petId = visit.providerClientPetId?.nonEmpty }
                next.assigneeId = visit.assignedMember?.id?.nonEmpty
            }
        }
        if next.clientId == nil, let pet = next.petId {
            next.clientId = await RecordsPetLookup.find(pet).clientId
        }
        members = await team.value ?? []
        context = next
    }
}
