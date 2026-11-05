//
//  Paging.swift
//  PawMiawNegocios
//
//  Full lists load 20 at a time with infinite scroll; counts come from the
//  server's `total`, never from what is loaded (the list loading policy).
//
//      @StateObject private var pager = Pager<Client> { offset, limit in
//          try await API.get("/provider-clients", query: ["offset": "\(offset)", "limit": "\(limit)", "q": search])
//      }
//      …
//      ForEach(pager.items) { client in Row(client).onAppear { pager.loadMoreIfNeeded(client) } }
//      PagerFooter(pager: pager)
//      .task { await pager.reload() }
//

import SwiftUI

@MainActor
final class Pager<Item: Decodable & Identifiable>: ObservableObject {
    typealias Fetch = (_ offset: Int, _ limit: Int) async throws -> Page<Item>

    @Published private(set) var items: [Item] = []
    @Published private(set) var total: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var loadedOnce = false
    private(set) var reachedEnd = false

    let pageSize: Int
    var fetch: Fetch
    private var generation = 0

    init(pageSize: Int = 20, fetch: @escaping Fetch) {
        self.pageSize = pageSize
        self.fetch = fetch
    }

    /// Starts again from the first page (a new search, a new filter, pull to refresh).
    func reload() async {
        generation += 1
        let mine = generation
        isLoading = true
        error = nil
        defer { if mine == generation { isLoading = false } }
        do {
            let page = try await fetch(0, pageSize)
            guard mine == generation else { return }
            items = page.items
            total = page.total
            reachedEnd = page.hasMore == false || page.items.count < pageSize || (page.total.map { page.items.count >= $0 } ?? false)
            loadedOnce = true
        } catch is CancellationError {
        } catch {
            guard mine == generation else { return }
            self.error = errorText(error)
            loadedOnce = true
        }
    }

    func loadMoreIfNeeded(_ item: Item) {
        guard !reachedEnd, !isLoadingMore, !isLoading else { return }
        let threshold = items.index(items.endIndex, offsetBy: -5, limitedBy: items.startIndex) ?? items.startIndex
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= threshold else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard !reachedEnd, !isLoadingMore else { return }
        let mine = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(items.count, pageSize)
            guard mine == generation else { return }
            let known = Set(items.map { "\($0.id)" })
            items += page.items.filter { !known.contains("\($0.id)") }
            if let t = page.total { total = t }
            reachedEnd = page.hasMore == false || page.items.count < pageSize || (total.map { items.count >= $0 } ?? false)
        } catch {
            self.error = errorText(error)
        }
    }

    /// Replaces one row in place after an edit.
    func replace(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
    }

    func remove(id: Item.ID) {
        items.removeAll { $0.id == id }
        if let t = total { total = max(0, t - 1) }
    }
}

/// The end of a paged list: a spinner while the next 20 load, the error with a retry.
struct PagerFooter<Item: Decodable & Identifiable>: View {
    @ObservedObject var pager: Pager<Item>

    var body: some View {
        Group {
            if pager.isLoadingMore {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            } else if let error = pager.error, !pager.items.isEmpty {
                VStack(spacing: 8) {
                    Text(error).font(Theme.smallFont).foregroundStyle(Theme.coralText)
                    PMButton(L("Try again"), variant: .outline, size: .compact) { Task { await pager.loadMore() } }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }
}

/// The whole state of a paged list in one view: loading, error, empty, rows.
struct PagedContent<Item: Decodable & Identifiable, Row: View, Empty: View>: View {
    @ObservedObject var pager: Pager<Item>
    @ViewBuilder let empty: () -> Empty
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        if !pager.loadedOnce && pager.isLoading {
            LoadingState()
        } else if let error = pager.error, pager.items.isEmpty {
            ErrorState(message: error) { await pager.reload() }
        } else if pager.items.isEmpty {
            empty()
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(pager.items) { item in
                    row(item).onAppear { pager.loadMoreIfNeeded(item) }
                }
                PagerFooter(pager: pager)
            }
        }
    }
}

/// A screen's one-shot load (a detail, a dashboard): loading, error with retry, or the value.
@MainActor
final class Loader<Value>: ObservableObject {
    @Published var value: Value?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let fetch: () async throws -> Value

    init(_ fetch: @escaping () async throws -> Value) { self.fetch = fetch }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { value = try await fetch() }
        catch is CancellationError {}
        catch { self.error = errorText(error) }
    }
}

/// Loading / error / content for a `Loader`.
struct LoadedContent<Value, Content: View>: View {
    @ObservedObject var loader: Loader<Value>
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value = loader.value {
            content(value)
        } else if let error = loader.error {
            ErrorState(message: error) { await loader.load() }
        } else {
            LoadingState()
        }
    }
}
