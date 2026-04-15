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
import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("audit render (throwaway)")
struct AuditRenderTests {

    @Test("/app sidebar still renders after field removal")
    func render() async throws {
        try await withTestApp { app in
            let user = try await app.makeUser(username: "alice", password: "alice-password-123")
            try await app.makeBookmark(for: user, url: "https://a.com", tags: ["swift/vapor"])
            var s = HTTPHeaders()
            try await app.testing().test(
                .POST,
                "app/login",
                beforeRequest: { req in try req.content.encode(
                    ["username": "alice", "password": "alice-password-123"],
                    as: .urlEncodedForm
                ) },
                afterResponse: { res async throws in
                    if let v = res.headers.setCookie?["stash_session"]?.string { s.replaceOrAdd(
                        name: .cookie,
                        value: "stash_session=\(v)"
                    ) }
                }
            )
            try await app.testing().test(.GET, "app", headers: s) { res async throws in
                #expect(res.status == .ok)
                let b = res.body.string
                #expect(b.contains("tag-sidebar"))
                #expect(b.contains(#"href="/app?tag=swift%2Fvapor""#)) // href still works
                #expect(b.contains(">vapor<")) // label still works
                #expect(!b.contains("position: fixed"))
                #expect(!b.contains("position: sticky"))
            }
        }
    }
}
