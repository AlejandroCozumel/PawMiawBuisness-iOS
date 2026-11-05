//
//  StockModels.swift
//  PawMiawNegocios
//
//  What Inventory and the Pharmacy read from the server, mirroring the web's
//  hooks (use-provider-store.ts `/provider-stock…`, use-prescriptions.ts
//  `/provider-prescriptions…`, `/provider-pharmacy…`). Anything the server
//  could leave out is Optional, so an older or newer answer never breaks
//  decoding; the few lists and numbers a screen always needs fall back to an
//  empty list or zero.
//

import Foundation

// MARK: - Inventory

nonisolated struct StockLot: Codable, Hashable, Identifiable {
    let id: String
    let lotCode: String?
    let expiresOn: String?
    let quantityOnHand: Int
    let unitCostAmount: Int?
    let receivedAt: String?

    init(id: String, lotCode: String?, expiresOn: String?, quantityOnHand: Int, unitCostAmount: Int?, receivedAt: String?) {
        self.id = id; self.lotCode = lotCode; self.expiresOn = expiresOn; self.quantityOnHand = quantityOnHand
        self.unitCostAmount = unitCostAmount; self.receivedAt = receivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        lotCode = try c.decodeIfPresent(String.self, forKey: .lotCode)
        expiresOn = try c.decodeIfPresent(String.self, forKey: .expiresOn)
        quantityOnHand = (try? c.decodeIfPresent(Int.self, forKey: .quantityOnHand)) ?? 0
        unitCostAmount = try? c.decodeIfPresent(Int.self, forKey: .unitCostAmount)
        receivedAt = try? c.decodeIfPresent(String.self, forKey: .receivedAt)
    }
}

nonisolated struct StockPack: Codable, Hashable {
    let catalogItemId: String
    let name: String
    let stockUnits: Int
    let unitAmount: Int?
}

/// A product's stock (`/provider-stock`), and — with `inventoryItemId` nil —
/// a product a delivery can be received for that is not counted yet
/// (`/provider-stock/products`).
nonisolated struct StockRow: Codable, Hashable, Identifiable {
    var inventoryItemId: String?
    var catalogItemId: String
    var name: String
    var sku: String?
    var barcode: String?
    var photoUrl: String?
    var productKind: String?
    var unitAmount: Int?
    var quantityOnHand: Int
    /// The count it is low at while its alert is on (its own, or the default of three).
    var reorderPoint: Int
    /// Cost and value at cost are business finances: null for anyone else.
    var unitCostAmount: Int?
    var stockValueAmount: Int?
    var allowBackorder: Bool
    var lowStock: Bool
    var outOfStock: Bool?
    var sellableUnits: Int?
    var lowStockAlert: Bool?
    var expiredUnits: Int?
    var trackLots: Bool?
    var nextExpiry: String?
    var lots: [StockLot]
    var packs: [StockPack]
    var tracked: Bool?
    var requiresPrescription: Bool?
    var controlSchedule: String?
    var storageLocation: String?
    var reorderQuantity: Int?

    var id: String { catalogItemId }

    init(inventoryItemId: String?, catalogItemId: String, name: String, sku: String?, barcode: String?, photoUrl: String?, productKind: String?, quantityOnHand: Int, reorderPoint: Int, unitCostAmount: Int?, lowStock: Bool, lots: [StockLot], packs: [StockPack], tracked: Bool?, controlSchedule: String?) {
        self.inventoryItemId = inventoryItemId; self.catalogItemId = catalogItemId; self.name = name; self.sku = sku
        self.barcode = barcode; self.photoUrl = photoUrl; self.productKind = productKind; self.unitAmount = nil
        self.quantityOnHand = quantityOnHand; self.reorderPoint = reorderPoint; self.unitCostAmount = unitCostAmount
        self.stockValueAmount = nil; self.allowBackorder = false; self.lowStock = lowStock; self.lots = lots; self.packs = packs
        self.tracked = tracked; self.requiresPrescription = true; self.controlSchedule = controlSchedule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inventoryItemId = try? c.decodeIfPresent(String.self, forKey: .inventoryItemId)
        catalogItemId = try c.decode(String.self, forKey: .catalogItemId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        sku = try? c.decodeIfPresent(String.self, forKey: .sku)
        barcode = try? c.decodeIfPresent(String.self, forKey: .barcode)
        photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        productKind = try? c.decodeIfPresent(String.self, forKey: .productKind)
        unitAmount = try? c.decodeIfPresent(Int.self, forKey: .unitAmount)
        quantityOnHand = (try? c.decodeIfPresent(Int.self, forKey: .quantityOnHand)) ?? 0
        reorderPoint = (try? c.decodeIfPresent(Int.self, forKey: .reorderPoint)) ?? 0
        unitCostAmount = try? c.decodeIfPresent(Int.self, forKey: .unitCostAmount)
        stockValueAmount = try? c.decodeIfPresent(Int.self, forKey: .stockValueAmount)
        allowBackorder = (try? c.decodeIfPresent(Bool.self, forKey: .allowBackorder)) ?? false
        lowStock = (try? c.decodeIfPresent(Bool.self, forKey: .lowStock)) ?? false
        outOfStock = try? c.decodeIfPresent(Bool.self, forKey: .outOfStock)
        sellableUnits = try? c.decodeIfPresent(Int.self, forKey: .sellableUnits)
        lowStockAlert = try? c.decodeIfPresent(Bool.self, forKey: .lowStockAlert)
        expiredUnits = try? c.decodeIfPresent(Int.self, forKey: .expiredUnits)
        trackLots = try? c.decodeIfPresent(Bool.self, forKey: .trackLots)
        nextExpiry = try? c.decodeIfPresent(String.self, forKey: .nextExpiry)
        lots = (try? c.decodeIfPresent([StockLot].self, forKey: .lots)) ?? []
        packs = (try? c.decodeIfPresent([StockPack].self, forKey: .packs)) ?? []
        tracked = try? c.decodeIfPresent(Bool.self, forKey: .tracked)
        requiresPrescription = try? c.decodeIfPresent(Bool.self, forKey: .requiresPrescription)
        controlSchedule = try? c.decodeIfPresent(String.self, forKey: .controlSchedule)
        storageLocation = try? c.decodeIfPresent(String.self, forKey: .storageLocation)
        reorderQuantity = try? c.decodeIfPresent(Int.self, forKey: .reorderQuantity)
    }
}

nonisolated struct StockMovement: Codable, Hashable, Identifiable {
    let id: String
    let movementType: String
    let quantityDelta: Int?
    let quantityAfter: Int?
    let unitCostAmount: Int?
    let notes: String?
    let lotCode: String?
    let folio: String?
    let invoiceId: String?
    let invoiceKind: String?
    let sourceType: String?
    let actorName: String?
    let occurredAt: String?
}

/// A Catalog product as the counter sells it (`/provider-store/products`): the prescription form picks medicines from it.
nonisolated struct StockStoreProduct: Codable, Hashable, Identifiable {
    nonisolated struct Stock: Codable, Hashable {
        let inventoryItemId: String?
        let available: Int?
        let lowStock: Bool?
    }
    let catalogItemId: String
    let itemType: String?
    let name: String
    let sku: String?
    let photoUrl: String?
    let productKind: String?
    let requiresPrescription: Bool?
    let controlSchedule: String?
    let stock: Stock?
    var id: String { catalogItemId }
}

// MARK: - Prescriptions

nonisolated struct StockFill: Codable, Hashable {
    let allowed: Int?
    let dispensed: Int?
    let remaining: Int?
    let fillsUsed: Int?
    let refillsLeft: Int?
}

nonisolated struct StockRxProduct: Codable, Hashable {
    let catalogItemId: String?
    let name: String?
    let active: Bool?
    let packOf: String?
    let unitsPerPack: Int?
}

nonisolated struct StockRxItem: Codable, Hashable, Identifiable {
    let id: String
    let catalogItemId: String?
    let medicineName: String
    let activeIngredient: String?
    let presentation: String?
    let strength: String?
    let doseAmount: Double?
    let doseUnit: String?
    let doseRate: Double?
    let doseRateUnit: String?
    let route: String?
    let everyHours: Double?
    let frequencyText: String?
    let asNeeded: Bool?
    let durationDays: Int?
    let quantity: Int?
    let quantityUnit: String?
    let refills: Int?
    let instructions: String?
    let withdrawalPeriod: String?
    let controlSchedule: String?
    let doseText: String?
    let fill: StockFill?
    let product: StockRxProduct?
    let countBasis: String?
    let closedAt: String?
    let closedByName: String?
    let closeNote: String?
    let handOverBlock: String?
    let nextFill: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        catalogItemId = try? c.decodeIfPresent(String.self, forKey: .catalogItemId)
        medicineName = (try? c.decodeIfPresent(String.self, forKey: .medicineName)) ?? ""
        activeIngredient = try? c.decodeIfPresent(String.self, forKey: .activeIngredient)
        presentation = try? c.decodeIfPresent(String.self, forKey: .presentation)
        strength = try? c.decodeIfPresent(String.self, forKey: .strength)
        doseAmount = try? c.decodeIfPresent(Double.self, forKey: .doseAmount)
        doseUnit = try? c.decodeIfPresent(String.self, forKey: .doseUnit)
        doseRate = try? c.decodeIfPresent(Double.self, forKey: .doseRate)
        doseRateUnit = try? c.decodeIfPresent(String.self, forKey: .doseRateUnit)
        route = try? c.decodeIfPresent(String.self, forKey: .route)
        everyHours = try? c.decodeIfPresent(Double.self, forKey: .everyHours)
        frequencyText = try? c.decodeIfPresent(String.self, forKey: .frequencyText)
        asNeeded = try? c.decodeIfPresent(Bool.self, forKey: .asNeeded)
        durationDays = try? c.decodeIfPresent(Int.self, forKey: .durationDays)
        quantity = try? c.decodeIfPresent(Int.self, forKey: .quantity)
        quantityUnit = try? c.decodeIfPresent(String.self, forKey: .quantityUnit)
        refills = try? c.decodeIfPresent(Int.self, forKey: .refills)
        instructions = try? c.decodeIfPresent(String.self, forKey: .instructions)
        withdrawalPeriod = try? c.decodeIfPresent(String.self, forKey: .withdrawalPeriod)
        controlSchedule = try? c.decodeIfPresent(String.self, forKey: .controlSchedule)
        doseText = try? c.decodeIfPresent(String.self, forKey: .doseText)
        fill = try? c.decodeIfPresent(StockFill.self, forKey: .fill)
        product = try? c.decodeIfPresent(StockRxProduct.self, forKey: .product)
        countBasis = try? c.decodeIfPresent(String.self, forKey: .countBasis)
        closedAt = try? c.decodeIfPresent(String.self, forKey: .closedAt)
        closedByName = try? c.decodeIfPresent(String.self, forKey: .closedByName)
        closeNote = try? c.decodeIfPresent(String.self, forKey: .closeNote)
        handOverBlock = try? c.decodeIfPresent(String.self, forKey: .handOverBlock)
        nextFill = try? c.decodeIfPresent(Int.self, forKey: .nextFill)
    }
}

nonisolated struct StockDispense: Codable, Hashable, Identifiable {
    nonisolated struct Lot: Codable, Hashable { let code: String?; let expiresOn: String?; let quantity: Int? }
    let id: String
    let prescriptionId: String?
    let prescriptionItemId: String?
    let documentFolio: String?
    let catalogItemId: String?
    let label: String?
    let quantity: Int?
    let sold: String?
    let kind: String?
    let controlSchedule: String?
    let providerClientId: String?
    let providerClientPetId: String?
    let petName: String?
    let clientName: String?
    let prescriberName: String?
    let prescriberCredential: String?
    let dispensedByName: String?
    let occurredAt: String?
    let counselledAt: String?
    let counselNote: String?
    let lots: [Lot]?
    let prescriptionFolio: String?
}

nonisolated struct StockRefill: Codable, Hashable, Identifiable {
    let id: String
    let prescriptionId: String?
    let prescriptionItemId: String?
    let status: String
    let note: String?
    let declineReason: String?
    let renewalPrescriptionId: String?
    let origin: String?
    let pickupSource: String?
    let pickupNote: String?
    let createdAt: String?
}

nonisolated struct StockShare: Codable, Hashable, Identifiable {
    let id: String
    let createdBySide: String?
    let tokenHint: String?
    let expiresAt: String?
    let viewCount: Int?
    let active: Bool?
}

nonisolated struct StockCreatedShare: Codable, Hashable, Identifiable {
    let id: String
    let token: String?
    let url: String
    let qrUrl: String?
    let expiresAt: String?
}

nonisolated struct StockSnapshot: Codable, Hashable {
    nonisolated struct Business: Codable, Hashable { let name: String?; let legalName: String?; let taxId: String?; let senasica: String?; let address: String?; let phone: String?; let email: String?; let locationName: String? }
    nonisolated struct Dea: Codable, Hashable { let number: String?; let registeredAddress: String? }
    nonisolated struct Prescriber: Codable, Hashable { let name: String?; let title: String?; let credentialType: String?; let credentialNumber: String?; let credentialRegion: String?; let credentialLine: String?; let dea: Dea? }
    nonisolated struct Client: Codable, Hashable { let name: String?; let phone: String?; let address: String? }
    nonisolated struct Age: Codable, Hashable { let years: Int?; let months: Int? }
    nonisolated struct Pet: Codable, Hashable { let name: String?; let species: String?; let breed: String?; let sex: String?; let birthDate: String?; let age: Age?; let weightKg: Double?; let microchip: String? }
    let folio: String?
    let signedAt: String?
    let validUntil: String?
    let country: String?
    let language: String?
    let legend: String?
    let controlled: Bool?
    let controlSchedule: String?
    let controlLabel: String?
    let business: Business?
    let prescriber: Prescriber?
    let client: Client?
    let pet: Pet?
    let diagnosis: String?
    let notes: String?
    let items: [StockRxItem]?
}

/// A prescription: the list's summary, and with the detail's extra fields when read on its own.
nonisolated struct StockPrescription: Codable, Hashable, Identifiable {
    nonisolated struct Integrity: Codable, Hashable { let verified: Bool?; let sha256: String? }
    let id: String
    let folio: String?
    let status: String
    let state: String
    let origin: String?
    let providerClientId: String
    let providerClientPetId: String
    let appointmentId: String?
    let petName: String?
    let petSpecies: String?
    let petBreed: String?
    let petPhotoUrl: String?
    let clientName: String?
    let familyLinked: Bool?
    let prescriberName: String?
    let diagnosis: String?
    let notes: String?
    let validUntil: String?
    let validDays: Int?
    let controlled: Bool?
    let language: String?
    let signedAt: String?
    let sharedWithFamilyAt: String?
    let cancelledAt: String?
    let cancelReason: String?
    let createdAt: String?
    let expiresSoon: Bool?
    let items: [StockRxItem]
    // The detail only.
    let snapshot: StockSnapshot?
    let integrity: Integrity?
    let dispenses: [StockDispense]?
    let shares: [StockShare]?
    let refillRequests: [StockRefill]?
    let canWrite: Bool?
    let canSign: Bool?
    let canCancel: Bool?
    let canDispenseAtVisit: Bool?
    let canLogRefill: Bool?
    let canHandOver: Bool?
    let canHandOverControlled: Bool?
    let canSell: Bool?
    let canCounsel: Bool?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        folio = try? c.decodeIfPresent(String.self, forKey: .folio)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "draft"
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "draft"
        origin = try? c.decodeIfPresent(String.self, forKey: .origin)
        providerClientId = (try? c.decodeIfPresent(String.self, forKey: .providerClientId)) ?? ""
        providerClientPetId = (try? c.decodeIfPresent(String.self, forKey: .providerClientPetId)) ?? ""
        appointmentId = try? c.decodeIfPresent(String.self, forKey: .appointmentId)
        petName = try? c.decodeIfPresent(String.self, forKey: .petName)
        petSpecies = try? c.decodeIfPresent(String.self, forKey: .petSpecies)
        petBreed = try? c.decodeIfPresent(String.self, forKey: .petBreed)
        petPhotoUrl = try? c.decodeIfPresent(String.self, forKey: .petPhotoUrl)
        clientName = try? c.decodeIfPresent(String.self, forKey: .clientName)
        familyLinked = try? c.decodeIfPresent(Bool.self, forKey: .familyLinked)
        prescriberName = try? c.decodeIfPresent(String.self, forKey: .prescriberName)
        diagnosis = try? c.decodeIfPresent(String.self, forKey: .diagnosis)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        validUntil = try? c.decodeIfPresent(String.self, forKey: .validUntil)
        validDays = try? c.decodeIfPresent(Int.self, forKey: .validDays)
        controlled = try? c.decodeIfPresent(Bool.self, forKey: .controlled)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        signedAt = try? c.decodeIfPresent(String.self, forKey: .signedAt)
        sharedWithFamilyAt = try? c.decodeIfPresent(String.self, forKey: .sharedWithFamilyAt)
        cancelledAt = try? c.decodeIfPresent(String.self, forKey: .cancelledAt)
        cancelReason = try? c.decodeIfPresent(String.self, forKey: .cancelReason)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresSoon = try? c.decodeIfPresent(Bool.self, forKey: .expiresSoon)
        items = (try? c.decodeIfPresent([StockRxItem].self, forKey: .items)) ?? []
        snapshot = try? c.decodeIfPresent(StockSnapshot.self, forKey: .snapshot)
        integrity = try? c.decodeIfPresent(Integrity.self, forKey: .integrity)
        dispenses = try? c.decodeIfPresent([StockDispense].self, forKey: .dispenses)
        shares = try? c.decodeIfPresent([StockShare].self, forKey: .shares)
        refillRequests = try? c.decodeIfPresent([StockRefill].self, forKey: .refillRequests)
        canWrite = try? c.decodeIfPresent(Bool.self, forKey: .canWrite)
        canSign = try? c.decodeIfPresent(Bool.self, forKey: .canSign)
        canCancel = try? c.decodeIfPresent(Bool.self, forKey: .canCancel)
        canDispenseAtVisit = try? c.decodeIfPresent(Bool.self, forKey: .canDispenseAtVisit)
        canLogRefill = try? c.decodeIfPresent(Bool.self, forKey: .canLogRefill)
        canHandOver = try? c.decodeIfPresent(Bool.self, forKey: .canHandOver)
        canHandOverControlled = try? c.decodeIfPresent(Bool.self, forKey: .canHandOverControlled)
        canSell = try? c.decodeIfPresent(Bool.self, forKey: .canSell)
        canCounsel = try? c.decodeIfPresent(Bool.self, forKey: .canCounsel)
    }

    var isSigned: Bool { status == "signed" }
    var isDraft: Bool { status == "draft" }
    var medicines: String { items.map(\.medicineName).joined(separator: ", ") }
}

nonisolated struct StockPrescriptionPage: Decodable {
    let items: [StockPrescription]
    let total: Int?
    let hasMore: Bool?
    let stateCounts: [String: Int]?
    let canWrite: Bool?
    let canSign: Bool?
}

// MARK: - Pharmacy

nonisolated struct StockHandOverTarget: Codable, Hashable {
    let prescriptionId: String?
    let prescriptionItemId: String?
    let folio: String?
    let catalogItemId: String?
    let productName: String?
    let remaining: Int?
    let quantity: Int?
    let block: String?
}

nonisolated struct StockRefillRequest: Codable, Hashable, Identifiable {
    let id: String
    let prescriptionId: String
    let prescriptionItemId: String?
    let status: String
    let note: String?
    let declineReason: String?
    let renewalPrescriptionId: String?
    let origin: String?
    let pickupSource: String?
    let createdAt: String?
    let folio: String?
    let providerClientId: String?
    let providerClientPetId: String?
    let petName: String?
    let petSpecies: String?
    let petPhotoUrl: String?
    let clientName: String?
    let familyLinked: Bool?
    let requestedByName: String?
    let loggedByName: String?
    let medicineName: String?
    let strength: String?
    let controlSchedule: String?
    let remaining: Int?
    let refillsLeft: Int?
    let validUntil: String?
    let needsRenewal: Bool?
    let handOver: StockHandOverTarget?
}

nonisolated struct StockRefillPage: Decodable {
    let items: [StockRefillRequest]
    let total: Int?
    let hasMore: Bool?
    let canApprove: Bool?
    let canMarkReady: Bool?
}

nonisolated struct StockHandOverLine: Codable, Hashable {
    let prescriptionItemId: String
    let medicineName: String?
    let strength: String?
    let quantityUnit: String?
    let controlSchedule: String?
    let catalogItemId: String?
    let productName: String?
    let remaining: Int?
    let quantity: Int?
    let block: String?
}

nonisolated struct StockHandOverRow: Codable, Hashable, Identifiable {
    nonisolated struct Bill: Codable, Hashable { let invoiceId: String?; let folio: String? }
    let key: String
    let kind: String?
    let requestId: String?
    let prescriptionId: String
    let folio: String?
    let providerClientId: String?
    let providerClientPetId: String?
    let appointmentId: String?
    let petName: String?
    let petSpecies: String?
    let petPhotoUrl: String?
    let clientName: String?
    let controlled: Bool?
    let since: String?
    let origin: String?
    let requestedByName: String?
    let note: String?
    let bill: Bill?
    let lines: [StockHandOverLine]?
    var id: String { key }
}

nonisolated struct StockHandOverPage: Decodable {
    let items: [StockHandOverRow]
    let total: Int?
    let hasMore: Bool?
}

nonisolated struct StockPharmacyCounts: Decodable {
    nonisolated struct Stock: Decodable { let low: Int?; let expiring: Int?; let expired: Int?; let either: Int?; let expiringDays: Int? }
    let toHandOver: Int?
    let refillsWaiting: Int?
    let refillsPending: Int?
    let draftsToSign: Int?
    let expiringSoon: Int?
    let expiringDays: Int?
    let badge: Int?
    let stock: Stock?
    let canWrite: Bool?
    let canSign: Bool?
    let canHandOver: Bool?
    let canHandOverControlled: Bool?
    let canLogRefill: Bool?
}

nonisolated struct StockRegisterMedicine: Codable, Hashable, Identifiable {
    nonisolated struct Discrepancy: Codable, Hashable { let registerBalance: Int?; let onHand: Int?; let difference: Int? }
    nonisolated struct Lot: Codable, Hashable { let id: String; let lotCode: String?; let expiresOn: String?; let quantityOnHand: Int? }
    let catalogItemId: String
    let inventoryItemId: String?
    let name: String
    let sku: String?
    let photoUrl: String?
    let active: Bool?
    let controlSchedule: String?
    let tracked: Bool?
    let onHand: Int?
    let registerBalance: Int?
    let discrepancy: Discrepancy?
    let movements: Int?
    let lastMovementAt: String?
    let reorderPoint: Int?
    let lowStock: Bool?
    let lots: [Lot]?
    let packs: [StockPack]?
    var id: String { catalogItemId }
}

nonisolated struct StockRegisterMedicines: Decodable {
    let today: String?
    let stockIsBusinessWide: Bool?
    let locations: Int?
    let items: [StockRegisterMedicine]
}

nonisolated struct StockRegisterLine: Codable, Hashable, Identifiable {
    let id: String
    let occurredAt: String?
    let type: String
    let quantity: Int?
    let balanceAfter: Int?
    let catalogItemId: String?
    let productName: String?
    let controlSchedule: String?
    let lotCode: String?
    let lotExpiresOn: String?
    let actorName: String?
    let note: String?
    let witnessName: String?
    let locationName: String?
    let documentFolio: String?
    let petName: String?
    let clientName: String?
    let prescriberName: String?
    let prescriberCredential: String?
    let prescriptionId: String?
    let prescriptionFolio: String?
    let dispenseId: String?
    let counselledAt: String?
    let counselNote: String?
    let doseText: String?
}

nonisolated struct StockControlledRegister: Decodable {
    nonisolated struct Medicine: Decodable { let catalogItemId: String?; let name: String?; let controlSchedule: String?; let onHand: Int? }
    let from: String?
    let to: String?
    let medicine: Medicine?
    let openingBalance: Int?
    let closingBalance: Int?
    let unitsIn: Int?
    let unitsOut: Int?
    let discrepancy: StockRegisterMedicine.Discrepancy?
    let truncated: Bool?
    let typeCounts: [String: Int]?
    let total: Int?
    let hasMore: Bool?
    let items: [StockRegisterLine]
}

nonisolated struct StockDispenseLog: Decodable {
    let from: String?
    let to: String?
    let items: [StockDispense]
    let total: Int?
    let hasMore: Bool?
    let canCounsel: Bool?
}

nonisolated struct StockPharmacyReport: Decodable {
    nonisolated struct Totals: Decodable { let dispenses: Int?; let units: Int?; let controlledUnits: Int?; let counselled: Int?; let prescriptionsSigned: Int?; let patients: Int?; let revenueAmount: Int? }
    nonisolated struct ByProduct: Decodable, Hashable { let label: String; let catalogItemId: String?; let units: Int?; let dispenses: Int?; let controlled: Bool?; let counselled: Int?; let revenueAmount: Int? }
    nonisolated struct ByPrescriber: Decodable, Hashable { let name: String; let dispenses: Int?; let revenueAmount: Int? }
    let from: String?
    let to: String?
    let totals: Totals
    let currency: String?
    let byProduct: [ByProduct]
    let byPrescriber: [ByPrescriber]
    let refills: [String: Int]
}

// MARK: - People the prescription sheet needs

nonisolated struct StockCredential: Codable, Hashable, Identifiable {
    nonisolated struct Label: Codable, Hashable { let es: String?; let en: String? }
    let id: String
    let type: String
    let label: Label?
    let number: String?
    let region: String?
    let prescribesHere: Bool?
    let allowsControlled: Bool?
}

nonisolated struct StockMemberCredentials: Decodable {
    let country: String?
    let requiredType: String?
    let items: [StockCredential]
    let canPrescribe: Bool?
    let canPrescribeControlled: Bool?
}

/// The few parts of the patient chart the prescription sheet reads: the weight and the allergies.
nonisolated struct StockChart: Decodable {
    nonisolated struct Weights: Decodable { let latestGrams: Int?; let latestAt: String? }
    nonisolated struct Allergy: Decodable {
        let label: String
        let draft: Bool?
        /// What the reaction was, and the record it is written in.
        var detail: String? = nil
        var recordId: String? = nil
    }
    nonisolated struct Summary: Decodable { let allergies: [Allergy]? }
    nonisolated struct Pet: Decodable { let name: String?; let weightGrams: Int?; let linked: Bool?; let species: String? }
    nonisolated struct Client: Decodable { let name: String?; var householdId: String? = nil }
    let pet: Pet?
    let client: Client?
    let weights: Weights?
    let summary: Summary?
}
