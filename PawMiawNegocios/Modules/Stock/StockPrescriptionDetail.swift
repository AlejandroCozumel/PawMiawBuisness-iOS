//
//  StockPrescriptionDetail.swift
//  PawMiawNegocios
//
//  One prescription (web prescriptions/prescription-view-sheet.tsx), on its
//  own page: its medicines with what is left and each time one was handed
//  out (and whether the owner was counselled), its refill requests, the link
//  and QR for an outside pharmacy (never for a controlled one) and the signed
//  snapshot as it prints. What its state allows: finish and sign a draft or
//  discard it, hand over what can be sold (the Store's counter, with the
//  client, the pet and each medicine against its line), add it to the
//  visit's bill, log a refill, mark a medicine fully dispensed or reopen it,
//  the PDF, and cancelling with its reason.
//

import SwiftUI
import UIKit
import QuickLook

struct StockPrescriptionScreen: View {
    let prescriptionId: String

    @EnvironmentObject private var workspace: Workspace
    @State private var prescription: StockPrescription?
    @State private var loadError: String?
    @State private var busy = false
    @State private var link: StockCreatedShare?
    @State private var cancelling = false
    @State private var discarding = false
    @State private var finishing = false
    @State private var logging = false
    @State private var counselling: StockCounselTarget?
    @State private var closing: StockRxItem?
    /// The PDF, open in Quick Look (which shares and prints it), as `DocumentButton` opens a server document.
    @State private var pdfURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let prescription {
                page(prescription)
            } else if let loadError {
                PageScroll { ErrorState(message: loadError) { await load() } }
            } else {
                PageScroll { LoadingState() }
            }
        }
        .providerPage(title)
        .reloadsOnScope { await load() }
        .sheet(isPresented: $cancelling) {
            ConfirmSheet(title: L("Cancel this prescription?"), message: L("Links stop working and nothing more can be dispensed from it."),
                         confirmTitle: L("Cancel prescription"), destructive: true, askReason: true, reasonRequired: true, reasonLabel: L("Why is it cancelled?"), cancelTitle: L("Keep it")) { reason in
                try await perform("POST", "/provider-prescriptions/\(prescriptionId)/cancel", body: ["reason": reason])
                Toast.show(L("Prescription cancelled. Nothing more can be dispensed from it."))
                await changed()
            }
        }
        .sheet(isPresented: $discarding) {
            ConfirmSheet(title: L("Discard this draft?"), message: L("It was never signed, so the family never saw it. It can’t be brought back."),
                         confirmTitle: L("Discard draft"), destructive: true, cancelTitle: L("Keep the draft")) { _ in
                try await perform("DELETE", "/provider-prescriptions/\(prescriptionId)", body: nil)
                Toast.show(L("Draft discarded."))
                announceDataChanged()
                dismiss()
            }
        }
        .sheet(item: $closing) { item in
            ConfirmSheet(title: L("Mark as fully dispensed?"),
                         message: L("Nothing more is handed over from this medicine, whatever is left on paper. Use it when what was sold covers what was prescribed. It can be reopened.") + "\n" + item.medicineName,
                         confirmTitle: L("Mark fully dispensed"), destructive: true, askReason: true, reasonRequired: false, reasonLabel: L("Note"), cancelTitle: L("Back@rx")) { note in
                try await perform("POST", "/provider-prescriptions/\(prescriptionId)/items/\(item.id)/close", body: ["closed": true, "note": note])
                Toast.show(L("Marked as fully dispensed."))
                await changed()
            }
        }
        .sheet(item: $counselling) { target in StockCounselSheet(target: target) }
        .sheet(isPresented: $logging) {
            if let prescription { StockLogRefillSheet(prescription: prescription) }
        }
        .sheet(isPresented: $finishing) {
            if let prescription {
                StockPrescriptionSheet(pet: StockRxPet(clientId: prescription.providerClientId, petId: prescription.providerClientPetId, petName: prescription.petName ?? "", species: prescription.petSpecies, photoUrl: prescription.petPhotoUrl, clientName: prescription.clientName),
                                       draft: prescription) { _ in Task { await load() } }
            }
        }
        .quickLookPreview($pdfURL)
    }

    private var title: String {
        guard let prescription else { return L("Prescription") }
        if let folio = prescription.folio?.nonEmpty { return LF("Prescription %@", folio) }
        return prescription.isDraft ? L("Prescription draft") : L("Prescription")
    }

    /// A request whose refusal comes back in the Pharmacy's words, for a ConfirmSheet to show.
    private func perform(_ method: String, _ path: String, body: [String: Any?]?) async throws {
        do {
            let _: EmptyResponse = try await StockAPI.send(method, path, body: body)
        } catch {
            throw APIError(status: (error as? StockRefusal)?.status ?? 400, message: StockRxWords.error(error), code: (error as? StockRefusal)?.code, fields: [:])
        }
    }

    private func load() async {
        do {
            prescription = try await API.get("/provider-prescriptions/\(prescriptionId)")
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = errorText(error)
        }
    }

    private func changed() async {
        await load()
        announceDataChanged()
    }

    // MARK: What can be handed over

    /// The lines a sale at the Store can hand over now.
    private func handOverLines(_ p: StockPrescription) -> [StockRxItem] {
        guard p.isSigned else { return [] }
        return p.items.filter { item in
            let block = item.handOverBlock ?? ((item.catalogItemId != nil && (item.fill?.remaining ?? 0) > 0) ? nil : "not_in_catalog")
            return block == nil && item.product?.active != false && item.catalogItemId != nil && (item.nextFill ?? item.fill?.remaining ?? 0) > 0
        }
    }

    private func handOverReason(_ p: StockPrescription) -> String? {
        guard !handOverLines(p).isEmpty else { return nil }
        if !(p.canSell ?? p.canHandOver ?? false) { return L("Someone who sells hands it over at the Store.") }
        if p.controlled == true && p.canHandOverControlled == false { return L("A controlled medicine is handed over by a vet. Ask one to do it.") }
        return nil
    }

    private func downloadPDF(_ p: StockPrescription) async {
        busy = true
        defer { busy = false }
        do {
            pdfURL = try await API.download("/provider-prescriptions/\(p.id)/pdf", fileName: p.folio ?? L("Prescription"))
        } catch {
            Toast.error(stockErrorText(error, fallback: L("The file couldn’t be downloaded. Try again.")))
        }
    }

    // MARK: Page

    private func page(_ p: StockPrescription) -> some View {
        PageScroll(refresh: { await load() }) {
            header(p)
            context(p)
            if p.status == "cancelled", let reason = p.cancelReason?.nonEmpty {
                NoticeCard(tone: .problem, message: LF("Cancelled %@: %@", StockText.day(p.cancelledAt), reason), icon: "ban")
            }
            if p.isDraft { NoticeCard(tone: .warning, message: L("A draft: not printed or shared until a vet signs it."), icon: "pen-line") }

            SectionCard(L("Medicines"), subtitle: p.isDraft ? nil : L("What is left to hand over, and what was handed out."), icon: "pill", accent: Theme.aqua) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(p.items) { item in medicineCard(item, p) }
                    if (p.isSigned && p.canLogRefill == true) || (p.isSigned && p.appointmentId != nil && p.canDispenseAtVisit == true) {
                        FlowLayout(spacing: 8) {
                            if p.isSigned && p.canLogRefill == true {
                                PMButton(L("Log a refill request"), systemImage: "bell-plus", variant: .outline) { logging = true }
                                    .disabled(busy)
                            }
                            if p.isSigned && p.appointmentId != nil && p.canDispenseAtVisit == true {
                                PMButton(L("Add to the visit’s bill"), systemImage: "receipt-text", variant: .outline, isWorking: busy) { Task { await addToBill(p) } }
                            }
                        }
                    }
                    if let reason = handOverReason(p) { Text(reason).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                }
                .padding(16)
            }

            if let requests = p.refillRequests, !requests.isEmpty {
                SectionCard(L("Refill requests"), icon: "bell-ring", accent: Theme.aqua) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(requests) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                FlowLayout(spacing: 8) {
                                    StockRefillPill(status: request.status)
                                    if request.origin == "staff" { StockRxChip(text: L("logged by the clinic")) }
                                    if let note = request.note?.nonEmpty { Text("“\(note)”").font(Theme.text(14)).foregroundStyle(Theme.inkStrong) }
                                    if let reason = request.declineReason?.nonEmpty { Text(LF("Reason: %@", reason)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft) }
                                    if request.pickupSource == "manual" {
                                        Text(request.pickupNote?.nonEmpty.map { LF("handed over outside a sale: %@", $0) } ?? L("handed over outside a sale")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                                    }
                                }
                                Text(StockText.dateTime(request.createdAt)).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
            }

            if p.isSigned { outsidePharmacy(p) }

            if let snapshot = p.snapshot {
                SectionCard(L("The prescription as it prints"), icon: "file-text", accent: Theme.aqua) {
                    StockPrescriptionDocument(header: StockDocHeader(snapshot: snapshot), items: (snapshot.items ?? []).map { StockDocItem($0) }, cancelled: p.status == "cancelled", integrity: p.integrity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                        .padding(16)
                }
            }
        }
    }

    /// The web modal's header: the folio, who signed it and when, and its actions (the modal's footer:
    /// discard or cancel, the PDF, finish and sign, hand over).
    private func header(_ p: StockPrescription) -> some View {
        let lines = handOverLines(p)
        let prefill = StockHandOver.prefill(p)
        return ModuleHeader(
            icon: "file-text",
            title: title,
            subtitle: [p.prescriberName, p.signedAt.map { StockText.day($0) } ?? LF("written %@", StockText.day(p.createdAt))].compactMap { $0?.nonEmpty }.joined(separator: " · "),
            accent: Theme.aqua,
            actionsOnRow: true,
            storageKey: "prescription"
        ) {
            if p.isDraft && p.canWrite == true {
                PMButton(L("Discard draft"), systemImage: "trash-2", variant: .destructive) { discarding = true }
                    .disabled(busy)
            }
            if p.isSigned && p.canCancel == true {
                PMButton(L("Cancel prescription"), systemImage: "ban", variant: .destructive) { cancelling = true }
                    .disabled(busy)
            }
            if p.snapshot != nil && !p.isDraft {
                PMButton(p.controlled == true ? L("Print original and copy") : L("Download PDF"), systemImage: p.controlled == true ? "printer" : "file-down", variant: .outline, isWorking: busy) {
                    Task { await downloadPDF(p) }
                }
            }
            if p.isDraft && (p.canWrite == true || p.canSign == true) {
                PMButton(p.canSign == true ? L("Finish and sign") : L("Finish the draft"), systemImage: "pen-line") { finishing = true }
                    .disabled(busy)
            }
            if !lines.isEmpty {
                NavigationLink(value: StockHandOver.route(prefill)) {
                    HStack(spacing: 6) { Glyph("shopping-cart", size: 16); Text(L("Hand over")) }
                }
                .buttonStyle(.pm(.primary, size: .header))
                .disabled(handOverReason(p) != nil || busy || prefill == nil)
            }
        }
    }

    /// Whose it is and what it is (web `ModalContextPills` and the chips under them).
    private func context(_ p: StockPrescription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                StockRxStatePill(state: p.state)
                if let client = p.clientName?.nonEmpty { Chip(text: client, tone: .muted, icon: "user-round") }
                if let pet = p.petName?.nonEmpty { Chip(text: pet, tone: .muted, icon: "paw-print") }
                if p.controlled == true { StockControlledChip() }
                if let until = p.validUntil { Chip(text: LF("Valid until %@", StockText.day(until)), tone: .muted) }
                if workspace.can(.clientsView) {
                    StockChartLink(clientId: p.providerClientId, petId: p.providerClientPetId, canViewClients: true)
                }
            }
            FlowLayout(spacing: 8) {
                if p.sharedWithFamilyAt != nil { StockRxChip(text: L("In the family’s app"), tone: Theme.blue) } else if p.familyLinked == false { StockRxChip(text: L("Family not on PawMiaw")) }
                if p.origin == "discharge" { StockRxChip(text: L("Hospital discharge"), tone: Hue.sky.color) }
                if p.origin == "renewal" { StockRxChip(text: L("Renewal"), tone: Hue.sky.color) }
                if p.expiresSoon == true { StockRxChip(text: L("Expires soon"), tone: Theme.mango, strong: true) }
            }
        }
    }

    private func addToBill(_ p: StockPrescription) async {
        busy = true
        defer { busy = false }
        do {
            let result: [String: JSONValue] = try await StockAPI.send("POST", "/provider-prescriptions/\(p.id)/visit-bill", body: [:])
            Toast.show((result["lines"]?.int ?? 0) > 0 ? L("Added to the visit’s bill.") : L("Nothing to add: its medicines aren’t Catalog products."))
            await changed()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }

    private func reopen(_ item: StockRxItem, _ p: StockPrescription) async {
        busy = true
        defer { busy = false }
        do {
            let _: EmptyResponse = try await StockAPI.send("POST", "/provider-prescriptions/\(p.id)/items/\(item.id)/close", body: ["closed": false, "note": nil])
            Toast.show(L("Reopened: it can be dispensed again."))
            await changed()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }

    private func withUnit(_ count: Int, _ unit: String?) -> String {
        unit?.nonEmpty.map { "\(count) \($0)" } ?? "\(count)"
    }

    /// One medicine (web `MedicineCard`): what was prescribed, what is left in its own unit, how it is
    /// counted when that isn't obvious, and each time it was handed out.
    private func medicineCard(_ item: StockRxItem, _ p: StockPrescription) -> some View {
        let dispenses = (p.dispenses ?? []).filter { $0.prescriptionItemId == item.id }
        let closed = item.closedAt != nil
        let canClose = p.canHandOver == true && p.isSigned
        let controlledBlocked = item.controlSchedule?.nonEmpty != nil && p.canHandOverControlled == false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    FlowLayout(spacing: 8) {
                        Text([item.medicineName, item.strength].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(16, weight: .bold)).foregroundStyle(Theme.inkStrong)
                        if let schedule = StockRxWords.schedule(item.controlSchedule) { StockControlledChip(label: schedule) }
                    }
                    Text(item.doseText?.nonEmpty ?? "—").font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                if let fill = item.fill {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(LF("%d of %@ left", fill.remaining ?? 0, withUnit(fill.allowed ?? 0, item.quantityUnit))).font(.brandHeading(20)).monospacedDigit().foregroundStyle(Theme.inkStrong).multilineTextAlignment(.trailing)
                        Text((fill.refillsLeft ?? 0) == 1 ? L("1 refill left") : LF("%d refills left", fill.refillsLeft ?? 0)).font(Theme.text(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            if p.isSigned && !closed {
                Group {
                    if item.countBasis == "bill" {
                        Text(L("Written in free text: each unit on a bill counts one, whatever its size. When what was sold covers it, mark it fully dispensed."))
                    } else if item.countBasis == "product", let product = item.product?.name {
                        Text(LF("Counted in units of %@: a pack counts what it holds.", product))
                    } else if item.countBasis == "pack", let product = item.product?.name {
                        Text(LF("Counted in packs of %@ (%d each).", product, item.product?.unitsPerPack ?? 1))
                    }
                }
                .font(Theme.text(12)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
            }
            if closed {
                FlowLayout(spacing: 8) {
                    StockRxChip(text: L("Fully dispensed"), tone: Hue.sky.color, icon: "check-check", strong: true)
                    Text([item.closedByName, item.closedAt.map { StockText.day($0) }, item.closeNote].compactMap { $0?.nonEmpty }.joined(separator: " · ")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 8)
            }
            if p.isSigned && !closed && item.handOverBlock == "not_in_catalog" {
                Text(StockRxWords.block("not_in_catalog") ?? "").font(Theme.text(12, weight: .semibold)).foregroundStyle(Theme.inkSoft).padding(.top, 8)
            }
            if !dispenses.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(dispenses.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { RowDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            (Text("\(entry.kind == "return" ? L("Came back") : L("Handed out")): \(abs(entry.quantity ?? 0))").fontWeight(.semibold).foregroundColor(Theme.inkStrong)
                             + Text(" · " + (entry.sold?.nonEmpty.map { LF("sold %@", $0) } ?? (entry.label ?? ""))).foregroundColor(Theme.inkSoft))
                                .font(Theme.text(14))
                            StockMetaLine(parts: [entry.documentFolio, entry.dispensedByName, StockText.dateTime(entry.occurredAt)])
                            if entry.kind != "return" {
                                if entry.counselledAt != nil {
                                    StockRxChip(text: L("Counselled") + (entry.counselNote?.nonEmpty.map { ": \($0)" } ?? ""), tone: Theme.lime, icon: "hand-heart")
                                } else if p.canCounsel == true {
                                    PMButton(L("Record counselling"), systemImage: "hand-heart", variant: .ghost, size: .modal) {
                                        counselling = StockCounselTarget(dispenseId: entry.id, label: entry.label ?? item.medicineName, petName: entry.petName)
                                    }
                                    .disabled(busy)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                .padding(.top, 12)
                .accessibilityLabel(LF("Handed out of %@", item.medicineName))
            }
            if canClose && (closed || (item.fill?.remaining ?? 0) > 0) {
                Group {
                    if closed {
                        PMButton(L("Reopen"), systemImage: "rotate-ccw", variant: .ghost, size: .modal) { Task { await reopen(item, p) } }
                    } else {
                        PMButton(L("Mark fully dispensed"), systemImage: "package-check", variant: .ghost, size: .modal) { closing = item }
                    }
                }
                .disabled(busy || controlledBlocked)
                .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 2))
    }

    // MARK: For an outside pharmacy

    private func outsidePharmacy(_ p: StockPrescription) -> some View {
        SectionCard(L("For an outside pharmacy"), icon: "qr-code", accent: Theme.aqua) {
            VStack(alignment: .leading, spacing: 12) {
                if p.controlled == true {
                    Text(L("A controlled prescription goes on paper, signed by hand — it can’t be sent as a link.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text(L("A read-only link and QR the pharmacy opens to check it. It expires in 7 days and you can stop it any time.")).font(Theme.text(14)).foregroundStyle(Theme.inkSoft)
                    if let link {
                        HStack(alignment: .center, spacing: 12) {
                            if let qr = APIConfig.assetURL(link.qrUrl) {
                                AsyncImage(url: qr) { phase in
                                    if let image = phase.image { image.resizable().interpolation(.none).scaledToFit() } else { ProgressView() }
                                }
                                .frame(width: 128, height: 128)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                                .accessibilityLabel(L("QR code of the link"))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(link.url).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                PMButton(L("Copy link"), systemImage: "copy", variant: .outline) {
                                    UIPasteboard.general.string = link.url
                                    Toast.show(L("Link copied."))
                                }
                                if let url = URL(string: link.url) {
                                    ShareLink(item: url) { HStack(spacing: 6) { Glyph("share-2", size: 16); Text(L("Share")) } }
                                        .buttonStyle(.pm(.outline))
                                }
                                if let expires = link.expiresAt { Text(LF("Expires %@", StockText.dateTime(expires))).font(Theme.text(12)).foregroundStyle(Theme.inkSoft) }
                            }
                        }
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: Theme.boxRadius, style: .continuous).strokeBorder(Theme.borderSoft, lineWidth: 1))
                    } else {
                        PMButton(L("Create link and QR"), systemImage: "qr-code", variant: .outline, isWorking: busy) { Task { await makeLink(p) } }
                    }
                    let active = (p.shares ?? []).filter { $0.active != false }
                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(active) { share in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .top, spacing: 6) {
                                        Glyph("link-2", size: 16).padding(.top, 2)
                                        Text([
                                            "…\(share.tokenHint ?? "")",
                                            share.createdBySide == "family" ? L("made by the family") : L("made here"),
                                            LF("seen %d times", share.viewCount ?? 0),
                                            LF("expires %@", StockText.day(share.expiresAt)),
                                        ].joined(separator: " · "))
                                    }
                                    .font(Theme.text(14)).foregroundStyle(Theme.inkStrong)
                                    PMButton(L("Stop link"), systemImage: "unlink", variant: .ghost, size: .modal) { Task { await stopLink(p, share) } }
                                        .disabled(busy)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func makeLink(_ p: StockPrescription) async {
        busy = true
        defer { busy = false }
        do {
            link = try await StockAPI.send("POST", "/provider-prescriptions/\(p.id)/shares", body: [:])
            await load()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }

    private func stopLink(_ p: StockPrescription, _ share: StockShare) async {
        busy = true
        defer { busy = false }
        do {
            let _: EmptyResponse = try await StockAPI.send("DELETE", "/provider-prescriptions/\(p.id)/shares/\(share.id)")
            if link?.id == share.id { link = nil }
            Toast.show(L("Link stopped."))
            await load()
        } catch {
            Toast.error(StockRxWords.error(error))
        }
    }
}
