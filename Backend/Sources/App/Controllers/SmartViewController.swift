// MIT License
//
// Copyright (c) 2026 Otávio C.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Fluent
import Vapor

/// Smart View CRUD and live query execution, scoped to the authenticated user (PRD §9.7).
struct SmartViewController: RouteCollection {

    // MARK: Static Functions

    // MARK: - Validation

    static func validatedName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.validationFailed("A Smart View name is required.")
        }
        guard trimmed.count <= SmartView.maxNameLength else {
            throw APIError.validationFailed("A Smart View name must be at most 100 characters.")
        }

        return trimmed
    }

    static func validatedConditions(_ payloads: [SmartViewConditionPayload]) throws -> [SmartViewCondition] {
        let conditions = try payloads.map { try SmartViewCondition.validated(type: $0.type, value: $0.value) }
        guard !conditions.isEmpty else {
            throw APIError.validationFailed("A Smart View needs at least one condition.")
        }

        return conditions
    }

    static func validatedMatchMode(_ raw: String?) throws -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "", SmartView.matchAll: SmartView.matchAll
        case SmartView.matchAny: SmartView.matchAny
        default: throw APIError.validationFailed("Match mode must be 'all' or 'any'.")
        }
    }

    // MARK: Functions

    func boot(routes: RoutesBuilder) throws {
        let smartViews = routes.grouped("smart-views")
        smartViews.get(use: list)
        smartViews.post(use: create)
        smartViews.group(":smartViewID") { smartView in
            smartView.get(use: get)
            smartView.put(use: update)
            smartView.delete(use: delete)
            smartView.get("bookmarks", use: bookmarks)
        }
    }

    func list(req: Request) async throws -> [SmartViewResponse] {
        let user = try req.auth.require(User.self)
        let smartViews = try await SmartView.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .sort(\.$name)
            .all()

        return try smartViews.map { try $0.asResponse() }
    }

    func create(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(SmartViewRequestBody.self)

        let name = try Self.validatedName(body.name)
        let conditions = try Self.validatedConditions(body.conditions)
        let matchMode = try Self.validatedMatchMode(body.matchMode)

        let smartView = try SmartView(
            userID: user.requireID(),
            name: name,
            conditions: conditions,
            matchMode: matchMode
        )
        try await smartView.save(on: req.db)

        let response = Response(status: .created)
        try response.content.encode(smartView.asResponse())
        return response
    }

    func get(req: Request) async throws -> SmartViewResponse {
        try await requireSmartView(req).asResponse()
    }

    func update(req: Request) async throws -> SmartViewResponse {
        let smartView = try await requireSmartView(req)
        let body = try req.content.decode(SmartViewRequestBody.self)

        smartView.name = try Self.validatedName(body.name)
        smartView.conditions = try Self.validatedConditions(body.conditions)
        if let rawMatchMode = body.matchMode {
            smartView.matchMode = try Self.validatedMatchMode(rawMatchMode)
        }

        try await smartView.save(on: req.db)
        return try smartView.asResponse()
    }

    func delete(req: Request) async throws -> Response {
        let smartView = try await requireSmartView(req)
        try await smartView.delete(on: req.db)
        return Response(status: .noContent)
    }

    func bookmarks(req: Request) async throws -> Page<BookmarkResponse> {
        let user = try req.auth.require(User.self)
        let smartView = try await requireSmartView(req)
        let query = try req.query.decode(BookmarkListQuery.self)

        let page = max(query.page ?? 1, 1)
        let per = min(max(query.per ?? 20, 1), 100)

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
        smartView.applyConditions(to: builder)

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let items = try result.items.map { try $0.asResponse() }
        return Page(items: items, metadata: result.metadata)
    }

    // MARK: - Helpers

    private func requireSmartView(_ req: Request) async throws -> SmartView {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("smartViewID", as: UUID.self),
              let smartView = try await SmartView.query(on: req.db)
                  .filter(\.$user.$id == user.requireID())
                  .filter(\.$id == id)
                  .first()
        else {
            throw APIError.smartViewNotFound
        }

        return smartView
    }
}
