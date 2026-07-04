// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Fluent
import Vapor

/// The tag browser (`/app/tags`) and tag rename/delete actions for the user-facing web frontend.
/// Session-cookie auth via `UserSessionMiddleware`; the mutations are delegated to the shared
/// `TagRenamer` / `TagDeleter` services so the web and the JSON API can't diverge.
struct TagWebController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("tags", use: tagBrowser)
        routes.post("tags", "rename", use: renameTag)
        routes.post("tags", "delete", use: deleteTag)
    }

    func tagBrowser(req: Request) async throws -> View {
        let user = try req.auth.require(User.self)
        let bookmarks = try await Bookmark.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .all()

        let tags = Bookmark.tagCounts(in: bookmarks).total
            .map { AppTagCount(name: $0.key, display: TagPresenter.display($0.key), count: $0.value) }
            .sorted { $0.name < $1.name }

        var message: String?
        switch req.query[String.self, at: "ok"] {
        case "renamed":
            let from = req.query[String.self, at: "from"] ?? ""
            let to = req.query[String.self, at: "to"] ?? ""
            let count = req.query[Int.self, at: "n"] ?? 0
            message = "Renamed \(from) to \(to) (\(count) bookmark\(count == 1 ? "" : "s") updated)."
        case "deleted":
            let tag = req.query[String.self, at: "tag"] ?? ""
            let count = req.query[Int.self, at: "n"] ?? 0
            message = "Deleted \(tag) (\(count) bookmark\(count == 1 ? "" : "s") updated)."
        default:
            message = nil
        }
        let error: String? = switch req.query[String.self, at: "error"] {
        case "rename": "Couldn't rename the tag — both names must be non-empty."
        case "delete": "Couldn't delete the tag — it must be a non-empty tag name."
        default: nil
        }

        return try await req.view.render("app-tags", AppTagsContext(
            title: "Tags", appUsername: user.username, appIsAdmin: user.role == .admin, tags: tags, message: message,
            error: error,
            chrome: req.siteChrome()
        ))
    }

    func renameTag(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(TagRenameForm.self)
        do {
            let result = try await TagRenamer.rename(
                rawFrom: form.from,
                rawTo: form.to,
                for: user.requireID(),
                on: req.db
            )
            let from = TagPresenter.queryValue(result.from)
            let to = TagPresenter.queryValue(result.to)
            return req.redirect(to: "/app/tags?ok=renamed&from=\(from)&to=\(to)&n=\(result.affectedBookmarks)")
        } catch is APIError {
            return req.redirect(to: "/app/tags?error=rename")
        }
    }

    func deleteTag(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let form = try req.content.decode(TagDeleteForm.self)
        do {
            let result = try await TagDeleter.delete(
                rawTag: form.tag,
                for: user.requireID(),
                on: req.db
            )
            let tag = TagPresenter.queryValue(result.tag)
            return req.redirect(to: "/app/tags?ok=deleted&tag=\(tag)&n=\(result.affectedBookmarks)")
        } catch is APIError {
            return req.redirect(to: "/app/tags?error=delete")
        }
    }
}
