// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

/// Public landing page at `/` (see the "Public landing page at `/`" entry in
/// `Docs/decisions-web.md`). Unauthenticated and unprotected;
/// it is the only web surface a visitor sees before signing in. It deliberately touches no session: the
/// `stash_session` cookie is path-scoped to `/app`, so reading or writing it from `/` would
/// clobber the visitor's logged-in session cookie. The page renders the same for everyone; a
/// signed-in visitor simply sees it rather than being redirected.
struct LandingController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get(use: index)
    }

    func index(req: Request) async throws -> Response {
        let chrome = req.siteChrome()
        let view: View = try await req.view.render("landing", LandingPageContext(
            title: "Welcome",
            chrome: chrome,
            aboutText: chrome.aboutText
        ))
        let response = Response(status: .ok)
        response.headers.contentType = .html
        response.body = .init(buffer: view.data)
        return response
    }
}
