//
//  CashFinanceExports.swift
//  PawMiawNegocios
//
//  Finance's spreadsheets (web: finance-collections.tsx `collectionsCsv`,
//  finance-payments.tsx `paymentsCsv`, finance-reports.tsx `salesCsv` and
//  `documentsCsv`), the same columns and totals row. Who owes is the front
//  desk's (level 2); payments and reports are business finances (level 3),
//  as their tabs are (docs/money-access-levels.md).
//

import Foundation

/// What an accountant asks for: one row per sale or bill (`/provider-finance/reports/documents`).
struct CashDocumentsReport: Decodable {
    struct Row: Decodable {
        let id: String
        let day: String
        let folio: String
        let source: String
        let status: String
        let walkIn: Bool?
        let clientName: String?
        let petName: String?
        let subtotal: Int
        let tax: Int
        let total: Int
        let returned: Int
        let paid: Int
        let balance: Int
        let methods: [String]?
        let references: [String]?
        let createdBy: String?
        let locationName: String?
    }
    struct Totals: Decodable { let documents: Int; let subtotal: Int; let tax: Int; let total: Int; let returned: Int; let paid: Int; let balance: Int }
    let currency: String?
    let rows: [Row]
    let totals: Totals
}

enum CashFinanceCSV {
    static func agingBucket(_ daysLate: Int) -> String {
        if daysLate <= 0 { return "current" }
        if daysLate <= 30 { return "d1_30" }
        if daysLate <= 60 { return "d31_60" }
        return "d61_plus"
    }

    /// The receivables list: one row per client, the buckets adding up to what they owe.
    static func collections(_ data: CashCollections) -> String {
        func aging(_ item: CashCollectionItem) -> [String: Int] {
            if let aging = item.aging { return aging }
            return [agingBucket(item.daysOverdue): item.owed]
        }
        var totals: [String: Int] = [:]
        for item in data.items {
            for (bucket, amount) in aging(item) { totals[bucket, default: 0] += amount }
        }
        let header = [L("Client"), L("Phone"), L("Email"), L("Pets"), L("Open bills"), L("Owes")] + CashText.agingBuckets.map(CashText.aging) + [L("Oldest due"), L("Days late"), L("Credit on account"), L("Credit limit"), L("Last contact")]
        var rows: [[String?]] = data.items.map { item in
            let buckets = aging(item)
            return [item.name, item.phone, item.email, (item.petNames ?? []).joined(separator: " / "), "\(item.documents)", CashCSV.money(item.owed)]
                + CashText.agingBuckets.map { CashCSV.money(buckets[$0] ?? 0) }
                + [item.oldestDueDay, "\(item.daysOverdue)", CashCSV.money(item.credit ?? 0), CashCSV.money(item.creditLimitAmount), item.lastContactAt.map { String($0.prefix(10)) } ?? ""]
        }
        rows.append([L("Total"), "", "", "", "\(data.items.reduce(0) { $0 + $1.documents })", CashCSV.money(data.items.reduce(0) { $0 + $1.owed })]
            + CashText.agingBuckets.map { CashCSV.money(totals[$0] ?? 0) } + ["", "", "", "", ""])
        return CashCSV.make(header: header, rows: rows)
    }

    /// What a row adds to "collected": money in, money back as a minus, credit on account nothing.
    static func ledgerAmount(_ row: CashLedgerItem) -> Int {
        if row.method == "credit" { return 0 }
        return row.kind == "refund" ? -row.amount : row.amount
    }

    /// Every payment and refund of the period; credit spent on a bill has its own column.
    static func payments(_ rows: [CashLedgerItem], zone: TimeZone?) -> String {
        let header = [L("Date"), L("Type"), L("Folio"), L("Client"), L("Pet"), L("Source"), L("Method"), L("Reference"), L("Amount"), L("Credit on account applied"), L("Collected by")]
        var lines: [[String?]] = rows.map { row in
            let credit = row.method == "credit"
            return [
                CashCSV.dateTime(row.paidAt, zone: zone),
                credit ? L("Credit on account applied") : row.kind == "refund" ? L("Refund") : L("Payment"),
                row.invoiceNumber, row.clientName, row.petName, CashText.source(row.source), CashText.method(row.method), row.reference,
                credit ? "" : CashCSV.money(ledgerAmount(row)),
                credit ? CashCSV.money(row.kind == "refund" ? -row.amount : row.amount) : "",
                row.collectedBy?.name ?? "",
            ]
        }
        let creditTotal = rows.reduce(0) { $0 + ($1.method == "credit" ? ($1.kind == "refund" ? -$1.amount : $1.amount) : 0) }
        lines.append([L("Total"), "", "", "", "", "", "", "", CashCSV.money(rows.reduce(0) { $0 + ledgerAmount($1) }), CashCSV.money(creditTotal), ""])
        return CashCSV.make(header: header, rows: lines)
    }

    /// The sales report as grouped on screen; cost and margin only for who may see them.
    static func sales(_ report: CashSalesReport, group: String, label: (CashSalesReport.Row) -> String, margin: Bool) -> String {
        let costed = report.totals.costed ?? report.rows.contains { $0.cost != nil }
        let header = [group, L("Sales and bills"), L("Quantity"), L("Before tax"), L("Tax"), L("Sold")] + (margin ? [L("Cost"), L("Margin")] : [])
        var rows: [[String?]] = report.rows.map { row in
            [report.groupBy == "day" ? row.key : label(row), "\(row.documents)", "\(row.quantity)",
             CashCSV.money(row.revenue - (row.tax ?? 0)), CashCSV.money(row.tax ?? 0), CashCSV.money(row.revenue)]
                + (margin ? [CashCSV.money(row.cost), CashCSV.money(row.margin)] : [])
        }
        rows.append([L("Total"), "\(report.totals.documents)", "\(report.totals.quantity)", CashCSV.money(report.totals.revenue - (report.totals.tax ?? 0)), CashCSV.money(report.totals.tax ?? 0), CashCSV.money(report.totals.revenue)]
            + (margin ? [costed ? CashCSV.money(report.totals.cost) : "", costed ? CashCSV.money(report.totals.margin) : ""] : []))
        return CashCSV.make(header: header, rows: rows)
    }

    private static func status(_ status: String) -> String {
        switch status {
        case "paid": L("Paid")
        case "partially_paid": L("Partly paid")
        case "overdue": L("Overdue")
        case "forgiven": L("Balance forgiven")
        default: L("Unpaid")
        }
    }

    /// One row per sale or bill: day, folio, client, amounts, how it was paid, what is owed.
    static func documents(_ report: CashDocumentsReport) -> String {
        let header = [L("Date"), L("Folio"), L("Source"), L("Client"), L("Pet"), L("Subtotal"), L("Tax"), L("Total"), L("Returned or credited"), L("Paid"), L("Balance"), L("Status"), L("Method"), L("Reference"), L("Made by"), L("Location")]
        var rows: [[String?]] = report.rows.map { row in
            [row.day, row.folio, CashText.source(row.source), row.clientName ?? (row.walkIn == true ? L("Walk-in sales") : ""), row.petName,
             CashCSV.money(row.subtotal), CashCSV.money(row.tax), CashCSV.money(row.total), CashCSV.money(row.returned), CashCSV.money(row.paid), CashCSV.money(row.balance),
             status(row.status), (row.methods ?? []).map { CashText.method($0) }.joined(separator: " + "), (row.references ?? []).joined(separator: " / "), row.createdBy, row.locationName]
        }
        let t = report.totals
        rows.append([L("Total"), "", "", "", "", CashCSV.money(t.subtotal), CashCSV.money(t.tax), CashCSV.money(t.total), CashCSV.money(t.returned), CashCSV.money(t.paid), CashCSV.money(t.balance), "", "", "", "", ""])
        return CashCSV.make(header: header, rows: rows)
    }
}
