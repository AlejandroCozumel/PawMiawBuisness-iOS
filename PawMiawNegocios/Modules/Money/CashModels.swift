//
//  CashModels.swift
//  PawMiawNegocios
//
//  The Money module's shapes, mirroring the web's hooks (use-provider-store,
//  use-provider-invoices, use-charging-queue, use-provider-finance,
//  use-provider-billing, use-provider-billing-summary). Amounts are integer
//  cents; dates are ISO strings. Anything a server may leave out is Optional.
//

import Foundation

// MARK: - People

struct CashActor: Codable, Hashable {
    let id: String?
    let name: String?
    let image: String?
}

/// A client as the pickers and the counter need it (`/provider-clients`).
// MARK: - Store

struct CashStoreSettings: Codable, Hashable {
    var currency: String
    var pricesIncludeTax: Bool
    var defaultTaxRateBps: Int
    var receiptFooter: String?
    var noShowFeeAmount: Int?
    var lateCancelWindowHours: Int?
    var cashDifferenceAlertAmount: Int?
    var openingCashDefault: Int?
    var stayDepositPercent: Int?
    var showPricesToFamilies: Bool?
    var currencyLocked: Bool?
    var currencyLockedReason: String?
    var emergencyDepositAmount: Int?
    var afterHoursSurchargeItemId: String?
    var emailReceipts: Bool?
}

struct CashProductStock: Codable, Hashable {
    let inventoryItemId: String?
    let unitsPerSale: Int?
    let available: Int?
    let allowBackorder: Bool?
    let reorderPoint: Int?
    let lowStock: Bool?
    let outOfStock: Bool?
    let lowStockAlert: Bool?
    let expiredUnits: Int?
}

struct CashProduct: Codable, Identifiable, Hashable {
    let catalogItemId: String
    let itemType: String
    let name: String
    let sku: String?
    let barcode: String?
    let photoUrl: String?
    let categoryId: String?
    let unitAmount: Int
    let currency: String?
    let productKind: String?
    let taxTreatment: String?
    let taxRateBps: Int?
    let requiresPrescription: Bool?
    let controlSchedule: String?
    let stock: CashProductStock?

    var id: String { catalogItemId }
    var isService: Bool { itemType == "service" }
    var rate: Int { taxRateBps ?? 0 }
    var needsPrescription: Bool { requiresPrescription ?? false }
}

struct CashSaleLot: Codable, Hashable {
    let lotCode: String?
    let expiresOn: String?
    let quantity: Int?
}

struct CashSaleLine: Codable, Identifiable, Hashable {
    let id: String
    let catalogItemId: String?
    let itemType: String
    let label: String
    let quantity: Int
    let unitAmount: Int
    let listUnitAmount: Int?
    let discountAmount: Int?
    let taxRateBps: Int?
    let taxAmount: Int?
    let totalAmount: Int
    let returnedQuantity: Int
    let restockedQuantity: Int?
    let tracksStock: Bool?
    let prescriptionFolio: String?
    let lots: [CashSaleLot]?
}

struct CashSalePayment: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let method: String
    let amount: Int
    let tenderedAmount: Int?
    let changeAmount: Int?
    let reference: String?
    let voidedAt: String?
    let paidAt: String?
}

struct CashSaleReturn: Codable, Identifiable, Hashable {
    let id: String
    let folio: String
    let reason: String?
    let refundAmount: Int
    let createdAt: String?
}

struct CashSale: Codable, Identifiable, Hashable {
    let id: String
    let folio: String
    let status: String
    let kind: String?
    let createdAt: String
    let currency: String
    let pricesIncludeTax: Bool?
    let providerClientId: String?
    let providerClientPetId: String?
    let walkIn: Bool
    let customerName: String?
    let petName: String?
    let cashierName: String?
    let registerSessionId: String?
    let subtotalAmount: Int
    let discountAmount: Int
    let discountReason: String?
    let taxAmount: Int
    let totalAmount: Int
    let amountPaid: Int
    let balanceDueAmount: Int
    let returnedAmount: Int
    let note: String?
    let cancelReason: String?
    let canceledAt: String?
    let lines: [CashSaleLine]
    let payments: [CashSalePayment]
    let returns: [CashSaleReturn]
}

struct CashSaleSummary: Codable, Identifiable, Hashable {
    let id: String
    let folio: String
    let status: String
    let createdAt: String
    let totalAmount: Int
    let balanceDueAmount: Int
    let returnedAmount: Int
    let currency: String
    let customerName: String?
    let walkIn: Bool
    let petName: String?
    let lineCount: Int?
    let unitCount: Int?
    let methods: [String]
    let cashierName: String?

    var canceled: Bool { status == "canceled" }
}

struct CashRegisterOpenSession: Codable, Hashable {
    let id: String
    let openedAt: String
    let openedByName: String?
    let stale: Bool?
    let timeZone: String?
}

struct CashRegister: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let openSessionId: String?
    let openSession: CashRegisterOpenSession?
    let lastCashLeft: Int?
    let defaultOpeningCash: Int?
    let locationId: String?
}

struct CashMethodFigure: Codable, Hashable {
    let method: String
    let payments: Int
    let refunds: Int
    let count: Int?
}

struct CashPersonFigure: Codable, Hashable {
    let userId: String?
    let name: String?
    let payments: Int
    let refunds: Int
    let count: Int?
    let net: Int?
}

struct CashMovement: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let amount: Int
    let reason: String?
    let actorName: String?
    let createdAt: String
}

struct CashSession: Codable, Identifiable, Hashable {
    let id: String
    let registerId: String?
    let registerName: String
    let status: String
    let openedAt: String
    let openedDay: String?
    let timeZone: String?
    let openedByName: String?
    let openingCash: Int
    let openingExpected: Int?
    let openingDifference: Int?
    let openingNote: String?
    let closedAt: String?
    let closedByName: String?
    let countedCash: Int?
    let difference: Int?
    let closingNote: String?
    let cashLeft: Int?
    let saleCount: Int
    let salesTotal: Int
    let returnCount: Int?
    let byMethod: [CashMethodFigure]
    let byPerson: [CashPersonFigure]?
    let cashIn: Int
    let cashOut: Int
    let expectedCash: Int
    let cardTotal: Int
    let cardTerminalTotal: Int?
    let cardDifference: Int?
    let denominations: [String: Int]?
    let frozen: Bool?
    let stale: Bool?
    let alertThreshold: Int?
    let cashMovements: [CashMovement]

    var isOpen: Bool { status == "open" }
    var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? Workspace.shared.timeZone }
}

struct CashCheckoutResult: Codable, Hashable {
    struct Bill: Codable, Hashable { let id: String; let folio: String; let paid: Int; let balance: Int }
    struct Receipt: Codable, Hashable { let emailedTo: String? }
    let saleId: String?
    let invoices: [Bill]
    let paid: Int
    let change: Int
    let balanceLeft: Int
    let receipt: Receipt?
}

/// A prescription line a product may be handed over against (`/provider-prescriptions/dispensable`).
struct CashDispensable: Codable, Identifiable, Hashable {
    let prescriptionItemId: String
    let folio: String?
    let medicineName: String?
    let remaining: Int?
    let prescriberName: String?
    let exactProduct: Bool?
    let unitsPerSale: Int?
    let validUntil: String?
    var id: String { prescriptionItemId }
}

struct CashDispensableList: Codable { let items: [CashDispensable] }

// MARK: - Invoices

struct CashCatalogSummary: Codable, Hashable {
    let id: String
    let name: String
    let defaultUnitAmount: Int?
}

struct CashInvoiceLine: Codable, Identifiable, Hashable {
    let id: String
    let providerCatalogItemId: String?
    let catalogItem: CashCatalogSummary?
    let itemType: String
    let label: String
    let description: String?
    let quantity: Int
    let unitAmount: Int
    let lineTotalAmount: Int?
    let taxTreatment: String?
    let taxRateBps: Int?
    let taxAmount: Int?
    let discountAmount: Int?
    let sortOrder: Int?
    let sourceType: String?
    let sourceId: String?
    let createdBy: CashActor?
    let listUnitAmount: Int?
    let priceOverriddenBy: CashActor?
    let sourceLabel: String?
    let changedAfterSent: Bool?
    let prescriptionItemId: String?
    let requiresPrescription: Bool?
    let controlSchedule: String?
    let courtesy: Bool?
    let adjustmentReason: String?
}

struct CashInvoicePayment: Codable, Identifiable, Hashable {
    let id: String
    let amount: Int
    let kind: String?
    let currency: String?
    let method: String
    let status: String?
    let reference: String?
    let notes: String?
    let paidAt: String?
    let collectedBy: CashActor?

    var isRefund: Bool { kind == "refund" }
    var voided: Bool { status == "voided" }
}

struct CashCreditNote: Codable, Identifiable, Hashable {
    let id: String
    let amount: Int
    let reason: String?
    let createdAt: String?
    let byName: String?
}

struct CashInvoice: Codable, Identifiable, Hashable {
    let id: String
    let providerClientId: String
    let providerClientPetId: String?
    let providerAppointmentId: String?
    let assignedMember: CashActor?
    let invoiceNumber: String
    let status: String
    let currency: String
    let subtotalAmount: Int
    let discountAmount: Int
    let discountReason: String?
    let taxAmount: Int
    let totalAmount: Int
    let amountPaid: Int
    let balanceDueAmount: Int
    let notes: String?
    let billingNote: String?
    let pdfUrl: String?
    let createdFromSourceType: String?
    let createdFromSourceId: String?
    let issuedAt: String?
    let dueAt: String?
    let finalizedAt: String?
    let clientName: String
    let clientPhotoUrl: String?
    let petName: String?
    let petPhotoUrl: String?
    let petSpecies: String?
    let kind: String?
    let origin: String?
    let refundedAmount: Int?
    let customerName: String?
    let pricesIncludeTax: Bool?
    let cancelReason: String?
    let canceledAt: String?
    let canceledBy: CashActor?
    /// "Perdonar saldo" (docs/family-money.md §1): what was forgiven, when, by whom and why.
    /// Always total − refunded = paid + forgiven + balance. Absent from an older server.
    let forgivenAmount: Int?
    let forgivenAt: String?
    let forgivenReason: String?
    let forgivenBy: CashActor?
    let locationId: String?
    let receiptEmailedTo: String?
    let lineItemCount: Int?
    let paymentCount: Int?
    let lineItems: [CashInvoiceLine]?
    let payments: [CashInvoicePayment]?
    let creditNotes: [CashCreditNote]?
    let createdBy: CashActor?
    let updatedBy: CashActor?
    let finalizedBy: CashActor?
    let revision: String?
    let createdAt: String
    let updatedAt: String?

    var lines: [CashInvoiceLine] { lineItems ?? [] }
    var allPayments: [CashInvoicePayment] { payments ?? [] }
    var refunded: Int { refundedAmount ?? 0 }
}

struct CashInvoiceSummary: Codable, Hashable {
    struct Count: Codable, Hashable { let count: Int; let amount: Int? }
    struct Draft: Codable, Hashable { let count: Int; let needsPrice: Int }
    struct Plain: Codable, Hashable { let count: Int }
    let due: Count
    let overdue: Count
    let draft: Draft
    let desk: Plain
    let partial: Plain
}

struct CashInvoiceTotals: Codable, Hashable {
    let billedAmount: Int
    let paidAmount: Int
    let balanceAmount: Int
    let draftAmount: Int?
    /// What was forgiven on the list's bills: out of billed, neither paid nor owed. Absent from an older server.
    let forgivenAmount: Int?
    let standingCount: Int
}

struct CashResolvedPeriod: Codable, Hashable {
    let from: String
    let to: String
    let today: String?
    let kind: String?
}

struct CashInvoicePage: Codable {
    let summary: CashInvoiceSummary?
    let totals: CashInvoiceTotals?
    let items: [CashInvoice]
    let period: CashResolvedPeriod?
    let today: String?
    let total: Int
    let hasMore: Bool?
}

struct CashChargingItem: Codable, Identifiable, Hashable {
    let source: String
    let sourceId: String
    let appointmentId: String?
    let invoiceId: String?
    let state: String
    let petName: String
    let petNames: [String]?
    let providerClientPetId: String?
    let clientName: String
    let providerClientId: String?
    let serviceLabel: String?
    let at: String
    let day: String
    let earlierDay: Bool
    let vetName: String?
    let amount: Int?
    let currency: String?

    var id: String { invoiceId ?? sourceId }
}

struct CashChargingQueue: Codable {
    struct Earlier: Codable { let count: Int; let oldestDay: String? }
    let scope: String?
    let count: Int
    let amount: Int?
    let earlierDays: Earlier?
    let items: [CashChargingItem]
    let today: String?
}

// MARK: - Finance

struct CashDashboard: Codable {
    struct Totals: Codable {
        let collected: Int
        let previousCollected: Int
        let refunded: Int
        let previousRefunded: Int?
        let paymentCount: Int?
        let refundCount: Int?
        let invoiced: Int
        let previousInvoiced: Int
        let tax: Int?
        let previousTax: Int?
        let subtotal: Int?
        let depositsReceived: Int?
        let creditApplied: Int?
        let creditHeld: Int?
        let creditClients: Int?
        let documents: Int
        let previousDocuments: Int
        let averageTicket: Int
        let previousAverageTicket: Int
        let margin: Int
        let marginCost: Int
        let marginRevenue: Int
        let previousMargin: Int
        let owed: Int
        let overdue: Int
        let clientsOwing: Int
    }
    struct Day: Codable, Hashable { let day: String; let collected: Int; let invoiced: Int }
    struct Source: Codable, Hashable { let source: String; let invoiced: Int; let documents: Int; let collected: Int }
    struct Method: Codable, Hashable { let method: String; let amount: Int; let count: Int; let refunds: Int? }
    struct Item: Codable, Hashable { let key: String; let label: String; let itemType: String?; let quantity: Int; let revenue: Int; let margin: Int? }
    struct Person: Codable, Hashable { let userId: String?; let name: String?; let image: String?; let documents: Int?; let revenue: Int?; let payments: Int?; let collected: Int? }
    struct TopClient: Codable, Hashable { let providerClientId: String; let name: String; let photoUrl: String?; let walkIn: Bool; let documents: Int; let invoiced: Int; let collected: Int }
    struct Cash: Codable {
        struct Item: Codable, Hashable { let id: String; let registerName: String; let day: String?; let difference: Int; let closedByName: String? }
        let closedShifts: Int
        let openShifts: Int
        let shiftsWithDifference: Int
        let short: Int
        let over: Int
        let net: Int
        let items: [Item]
    }
    struct Inventory: Codable { let tracked: Int; let valueAmount: Int; let lowStock: Int; let outOfStock: Int; let expiringSoon: Int; let expired: Int?; let expiringDays: Int? }
    struct Place: Codable, Hashable { let locationId: String; let name: String; let status: String?; let isPrimary: Bool?; let collected: Int; let invoiced: Int; let documents: Int }

    let currency: String
    let timeZone: String?
    let period: CashResolvedPeriod?
    let totals: Totals
    let days: [Day]
    let sources: [Source]
    let methods: [Method]
    let topItems: [Item]
    let staff: [Person]
    let collectors: [Person]?
    let topClients: [TopClient]?
    let aging: [String: Int]?
    let cash: Cash?
    let inventory: Inventory?
    let locationId: String?
    let byLocation: [Place]?
}

struct CashPromise: Codable, Hashable {
    let id: String
    let promisedAmount: Int?
    let promisedOn: String
    let status: String
}

struct CashCollectionItem: Codable, Identifiable, Hashable {
    let providerClientId: String
    let name: String
    let firstName: String?
    let photoUrl: String?
    let phone: String?
    let email: String?
    let onPawMiaw: Bool?
    /// The family unlinked (or the business did): "Se desconectó de PawMiaw el {fecha}". Absent from an older server.
    let disconnectedAt: String?
    let disconnectedBy: String?
    let walkIn: Bool?
    let creditLimitAmount: Int?
    let overLimit: Bool?
    let currency: String?
    let owed: Int
    let aging: [String: Int]?
    let credit: Int?
    let overdue: Int
    let documents: Int
    let oldestDueDay: String?
    let daysOverdue: Int
    let petNames: [String]?
    let promise: CashPromise?
    let lastContactAt: String?
    let lastContactKind: String?
    let lastContactChannel: String?

    var id: String { providerClientId }
}

struct CashCollections: Codable {
    struct Summary: Codable {
        let owed: Int
        let overdue: Int
        let clients: Int
        let overdueClients: Int
        let promisesDue: Int
        let promisesBroken: Int
        let promisesPending: Int
        let overLimit: Int
        let uncontacted: Int
        let aging: [String: Int]?
        let agingClients: [String: Int]?
        let creditHeld: Int?
        let creditClients: Int?
        let currency: String
    }
    struct Credit: Codable, Identifiable, Hashable { let providerClientId: String; let name: String; let photoUrl: String?; let credit: Int; let owed: Int; var id: String { providerClientId } }
    let today: String
    let summary: Summary
    let items: [CashCollectionItem]
    let credits: [Credit]?
}

struct CashAccount: Codable {
    struct Client: Codable {
        let id: String
        let name: String
        let firstName: String?
        let photoUrl: String?
        let phone: String?
        let email: String?
        let onPawMiaw: Bool?
        /// Unlinked: what they owe from before stays theirs, and a reminder in PawMiaw still reaches the bills' family.
        let disconnectedAt: String?
        let disconnectedBy: String?
        let walkIn: Bool?
        let creditLimitAmount: Int?
    }
    struct Open: Codable, Identifiable, Hashable {
        let id: String
        let folio: String
        let source: String
        let status: String
        let petName: String?
        let totalAmount: Int
        let refundedAmount: Int?
        let amountPaid: Int
        let balanceDueAmount: Int
        let issuedAt: String?
        let dueDay: String?
        let daysOverdue: Int
    }
    struct Entry: Codable, Hashable {
        let at: String
        let type: String
        let id: String
        let folio: String?
        let label: String?
        let amount: Int
        let method: String?
        let source: String?
        let balance: Int
    }
    struct Note: Codable, Identifiable, Hashable {
        let id: String
        let kind: String
        let body: String?
        let channel: String?
        let promisedAmount: Int?
        let promisedOn: String?
        let promiseStatus: String?
        let balanceAmount: Int?
        let author: String?
        let createdAt: String
    }
    let client: Client
    let credit: Int
    let currency: String
    let timeZone: String?
    let today: String
    let owed: Int
    let overdue: Int
    let open: [Open]
    let statement: [Entry]
    let notes: [Note]
}

struct CashCollectResult: Codable {
    let collected: Int
    let owedAfter: Int
    let replayed: Bool?
}

struct CashLedgerItem: Codable, Identifiable, Hashable {
    let id: String
    let providerInvoiceId: String
    let amount: Int
    let kind: String
    let method: String
    let reference: String?
    let paidAt: String?
    let source: String?
    let invoiceNumber: String
    let providerClientId: String?
    let clientName: String
    let petName: String?
    let serviceLabel: String?
    let daysLate: Int?
    let collectedBy: CashActor?
}

struct CashLedgerPage: Codable {
    struct Summary: Codable {
        let totalAmount: Int
        let refundedAmount: Int
        let paymentCount: Int?
        let refundCount: Int?
        let creditAppliedAmount: Int?
        let creditCount: Int?
    }
    let items: [CashLedgerItem]
    let summary: Summary
    let total: Int
    let hasMore: Bool
}

struct CashDayClose: Codable {
    struct Method: Codable, Hashable { let method: String; let payments: Int; let refunds: Int; let net: Int; let count: Int }
    struct Credit: Codable { let spent: Int; let returned: Int; let count: Int }
    struct Source: Codable, Hashable { let source: String; let net: Int; let count: Int }
    struct Totals: Codable { let collected: Int; let refunded: Int; let net: Int; let payments: Int; let refunds: Int }
    struct Outside: Codable { let net: Int; let count: Int }
    struct Refund: Codable, Identifiable, Hashable { let id: String; let at: String; let amount: Int; let method: String; let folio: String; let invoiceId: String; let clientName: String?; let by: String?; let reason: String? }
    struct Place: Codable, Hashable { let locationId: String; let name: String; let status: String?; let net: Int; let payments: Int; let refunds: Int; let openShifts: Int }
    struct ShiftTotals: Codable { let shifts: Int; let open: Int; let cashExpected: Int; let cashCounted: Int; let cashDifference: Int; let cardTotal: Int; let cardTerminalTotal: Int?; let cardDifference: Int? }
    let day: String
    let today: String
    let isToday: Bool
    let timeZone: String?
    let currency: String
    let byMethod: [Method]
    let credit: Credit
    let bySource: [Source]
    let byPerson: [CashPersonFigure]
    let totals: Totals
    let outsideShifts: Outside?
    let refundItems: [Refund]
    let creditRefundItems: [Refund]?
    let shifts: [CashSession]
    let byLocation: [Place]?
    let shiftTotals: ShiftTotals
}

struct CashException: Codable, Identifiable, Hashable {
    struct Link: Codable, Hashable { let to: String; let id: String }
    let id: String
    let kind: String
    let at: String
    let actorName: String?
    let amount: Int
    let currency: String?
    let reason: String?
    let clientName: String?
    let petName: String?
    let documentId: String?
    let documentFolio: String?
    let documentKind: String?
    let sessionId: String?
    let registerName: String?
    let link: Link
    let direction: String?
    let method: String?
    let paidWith: [String]?
    let lineLabel: String?
    let paidOn: String?
    let visitOn: String?
}

struct CashExceptions: Codable {
    let day: String
    let timeZone: String?
    let currency: String
    let total: Int
    let withoutReason: Int
    let items: [CashException]
    /// The server's count for each kind ("forgiven" included); absent from an older server.
    let counts: [String: Int]?
}

struct CashSalesReport: Codable {
    struct Row: Codable, Identifiable, Hashable { let key: String; let label: String; let detail: String?; let documents: Int; let quantity: Int; let revenue: Int; let tax: Int?; let cost: Int?; let margin: Int?; var id: String { key } }
    struct Totals: Codable { let documents: Int; let quantity: Int; let revenue: Int; let tax: Int?; let cost: Int; let margin: Int; let costed: Bool? }
    let currency: String
    let groupBy: String
    let rows: [Row]
    let totals: Totals
}

// MARK: - Catalog

struct CashCategory: Codable, Identifiable, Hashable {
    let id: String
    let itemType: String
    let name: String
    let active: Bool
}

struct CashCategoryList: Codable { let items: [CashCategory] }

struct CashInventorySummary: Codable, Hashable {
    /// The stock record's id (a delivery receives against it).
    let id: String?
    let barcode: String?
    let storageLocation: String?
    let unitCostAmount: Int?
    let quantityOnHand: Int
    let reorderPoint: Int
    let reorderQuantity: Int?
    let allowBackorder: Bool
    let lowStock: Bool
    let lowStockAlert: Bool?
    let expiredUnits: Int?
}

struct CashCatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let itemType: String
    let category: CashCategory?
    let name: String
    let photoUrl: String?
    let description: String?
    let sku: String?
    let currency: String?
    let defaultUnitAmount: Int
    let active: Bool
    let trackInventory: Bool
    let productKind: String?
    let taxTreatment: String
    let taxRateBps: Int?
    let requiresPrescription: Bool
    let controlSchedule: String?
    let stockCatalogItemId: String?
    let stockUnits: Int?
    let inventory: CashInventorySummary?
    let updatedAt: String?

    var isProduct: Bool { itemType == "product" }
    var isPack: Bool { isProduct && stockCatalogItemId != nil }
}

struct CashCatalogUsage: Codable {
    struct Pack: Codable, Hashable { let id: String; let name: String }
    let packs: [Pack]
    let serviceIds: [String]
    let openBills: Int
    let stockOnHand: Int
    let prescriptions: Int?
    let hospitalOrders: Int?
}

// MARK: - Subscription

struct CashBillingSummary: Codable {
    struct Charge: Codable { let amount: Int; let currency: String; let date: String? }
    struct Card: Codable { let brand: String?; let last4: String?; let expMonth: Int?; let expYear: Int? }
    struct Receipt: Codable, Identifiable, Hashable { let id: String; let number: String?; let date: String; let amount: Int; let currency: String; let status: String; let url: String?; let pdfUrl: String? }
    let available: Bool
    let reachable: Bool
    let billingCycle: String?
    let nextCharge: Charge?
    let card: Card?
    let receipts: [Receipt]
}

struct CashMember: Codable, Identifiable { let id: String }
struct CashInvitation: Codable, Identifiable { let id: String; let status: String?; let expiresAt: String? }
