// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

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
        req.logger.info("\(ActivityLog.smartViewCreated(name: name, user: user.username))")

        let response = Response(status: .created)
        try response.content.encode(smartView.asResponse())
        return response
    }

    func get(req: Request) async throws -> SmartViewResponse {
        try await requireSmartView(req).asResponse()
    }

    func update(req: Request) async throws -> SmartViewResponse {
        let user = try req.auth.require(User.self)
        let smartView = try await requireSmartView(req)
        let body = try req.content.decode(SmartViewRequestBody.self)

        smartView.name = try Self.validatedName(body.name)
        smartView.conditions = try Self.validatedConditions(body.conditions)
        if let rawMatchMode = body.matchMode {
            smartView.matchMode = try Self.validatedMatchMode(rawMatchMode)
        }

        try await smartView.save(on: req.db)
        req.logger.info("\(ActivityLog.smartViewUpdated(name: smartView.name, user: user.username))")
        return try smartView.asResponse()
    }

    func delete(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let smartView = try await requireSmartView(req)
        let name = smartView.name
        try await smartView.delete(on: req.db)
        req.logger.info("\(ActivityLog.smartViewDeleted(name: name, user: user.username))")
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
