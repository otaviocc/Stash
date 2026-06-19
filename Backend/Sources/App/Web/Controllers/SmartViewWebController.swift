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

/// Smart Views for the user-facing web frontend (`/app/smart-views/*`): browse a saved view's live
/// results (reusing the bookmark-list template) and manage views (list / create / edit / delete).
/// Session-cookie auth via `UserSessionMiddleware`; validation and querying are delegated to the Core
/// `SmartView` / `SmartViewController` and presentation to `SmartViewPresenter`.
struct SmartViewWebController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        let smartViews = routes.grouped("smart-views")
        smartViews.get(use: smartViewManage)
        smartViews.get("new", use: newSmartViewForm)
        smartViews.post("new", use: createSmartView)
        smartViews.get(":smartViewID", use: smartViewResults)
        smartViews.get(":smartViewID", "edit", use: editSmartViewForm)
        smartViews.post(":smartViewID", "edit", use: updateSmartView)
        smartViews.post(":smartViewID", "delete", use: deleteSmartView)
    }

    // MARK: - Results

    func smartViewResults(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        let overridesArchived = smartView.conditions.contains { if case .isArchived = $0 { true } else { false } }
        let archived = !overridesArchived && (req.query[Bool.self, at: "archived"] ?? false)
        let page = max(req.query[Int.self, at: "page"] ?? 1, 1)
        let per = WebPagination.perPage
        let boundaries = Bookmark.dateBoundaries()

        let builder = try Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
        smartView.applyConditions(to: builder, archivedDefault: archived)

        let result = try await builder
            .sort(\.$createdAt, .descending)
            .sort(\.$id, .descending)
            .paginate(PageRequest(page: page, per: per))

        let total = result.metadata.total
        let pageCount = WebPagination.pageCount(total: total)
        let sidebar = try await AppSidebarLoader.load(
            for: user,
            activeTag: "",
            activeSmartViewID: id,
            today: boundaries.today,
            week: boundaries.week,
            on: req.db
        )

        return try await req.renderHTML("app-bookmarks", AppBookmarksContext(
            title: smartView.name,
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            bookmarks: result.items.map { try BookmarkPresenter.row(from: $0) },
            q: "",
            tag: "",
            tagDisplay: "",
            archived: archived,
            archiveToggleURL: "",
            total: total,
            page: page,
            pageCount: pageCount,
            prevURL: page > 1 ? SmartViewPresenter.smartViewListURL(id: id, archived: archived, page: page - 1) : nil,
            nextURL: page < pageCount ? SmartViewPresenter
                .smartViewListURL(id: id, archived: archived, page: page + 1) : nil,
            notice: nil,
            sidebarTags: sidebar.tags,
            untaggedCount: sidebar.untaggedCount,
            untaggedActive: false,
            todayCount: sidebar.todayCount,
            todayActive: false,
            thisWeekCount: sidebar.thisWeekCount,
            thisWeekActive: false,
            smartViews: sidebar.smartViews,
            isSmartView: true,
            smartViewID: id,
            showArchivedToggle: !overridesArchived,
            chrome: req.siteChrome()
        ))
    }

    // MARK: - Manage

    func smartViewManage(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let smartViews = try await SmartView.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .sort(\.$name)
            .all()
        let rows = try smartViews.map { view in
            try AppSmartViewRow(
                id: view.requireID().uuidString,
                name: view.name,
                summary: SmartViewPresenter.summary(for: view.conditions, matchMode: view.matchMode)
            )
        }
        let message: String? = switch req.query[String.self, at: "ok"] {
        case "saved": "Smart View saved."
        case "deleted": "Smart View deleted."
        default: nil
        }

        return try await req.view.render("app-smart-views", AppSmartViewsContext(
            title: "Smart Views",
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            smartViews: rows,
            message: message,
            chrome: req.siteChrome()
        ))
    }

    func newSmartViewForm(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)

        return try await renderSmartViewForm(
            req, user,
            title: "New Smart View",
            isEdit: false,
            action: "/app/smart-views/new",
            name: "",
            matchMode: SmartView.matchAll,
            conditions: [SmartViewPresenter.defaultField],
            error: nil
        )
    }

    func createSmartView(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(SmartViewForm.self)

        do {
            let name = try SmartViewController.validatedName(form.name)
            let matchMode = try SmartViewController.validatedMatchMode(form.matchMode)
            let conditions = try SmartViewPresenter.conditions(from: form)
            let smartView = try SmartView(
                userID: user.requireID(),
                name: name,
                conditions: conditions,
                matchMode: matchMode
            )
            try await smartView.save(on: req.db)

            return req.redirect(to: "/app/smart-views?ok=saved")
        } catch let error as APIError {
            return try await renderSmartViewForm(
                req, user,
                title: "New Smart View",
                isEdit: false,
                action: "/app/smart-views/new",
                name: form.name,
                matchMode: form.matchMode ?? SmartView.matchAll,
                conditions: SmartViewPresenter.fields(from: form),
                error: error.reason,
                status: .unprocessableEntity
            )
        }
    }

    func editSmartViewForm(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        return try await renderSmartViewForm(
            req, user,
            title: "Edit Smart View",
            isEdit: true,
            action: "/app/smart-views/\(id)/edit",
            name: smartView.name,
            matchMode: smartView.matchMode,
            conditions: smartView.conditions.map { SmartViewPresenter.field(from: $0) },
            error: nil
        )
    }

    func updateSmartView(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        let id = try smartView.requireID().uuidString
        let form = try req.content.decode(SmartViewForm.self)

        do {
            smartView.name = try SmartViewController.validatedName(form.name)
            smartView.matchMode = try SmartViewController.validatedMatchMode(form.matchMode)
            smartView.conditions = try SmartViewPresenter.conditions(from: form)
            try await smartView.save(on: req.db)

            return req.redirect(to: "/app/smart-views?ok=saved")
        } catch let error as APIError {
            return try await renderSmartViewForm(
                req, user,
                title: "Edit Smart View",
                isEdit: true,
                action: "/app/smart-views/\(id)/edit",
                name: form.name,
                matchMode: form.matchMode ?? SmartView.matchAll,
                conditions: SmartViewPresenter.fields(from: form),
                error: error.reason,
                status: .unprocessableEntity
            )
        }
    }

    func deleteSmartView(req: Request) async throws -> Response {
        guard let smartView = try await loadSmartView(req) else { return req.redirect(to: "/app/smart-views") }

        try await smartView.delete(on: req.db)
        return req.redirect(to: "/app/smart-views?ok=deleted")
    }

    // MARK: - Helpers

    private func loadSmartView(_ req: Request) async throws -> SmartView? {
        let user = try req.auth.require(User.self)
        guard let id = req.parameters.get("smartViewID", as: UUID.self) else { return nil }

        return try await SmartView.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .filter(\.$id == id)
            .first()
    }

    private func renderSmartViewForm(
        _ req: Request,
        _ user: User,
        title: String,
        isEdit: Bool,
        action: String,
        name: String,
        matchMode: String,
        conditions: [SmartViewConditionField],
        error: String?,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        try await req.renderHTML("app-smart-view-form", AppSmartViewFormContext(
            title: title,
            appUsername: user.username,
            appIsAdmin: user.role == .admin,
            error: error,
            isEdit: isEdit,
            action: action,
            name: name,
            matchMode: matchMode,
            conditions: conditions,
            knownTagsJSON: KnownTags.json(for: user, on: req.db),
            chrome: req.siteChrome()
        ), status: status)
    }
}
