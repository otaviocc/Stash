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

import Vapor

/// Public landing page at `/` (PRD §1). Unauthenticated and unprotected — it is the only web
/// surface a visitor sees before signing in. It deliberately touches no session: the
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
