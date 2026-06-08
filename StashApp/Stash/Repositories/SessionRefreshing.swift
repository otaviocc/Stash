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

import Foundation

/// A session that vends a client which keeps the access token fresh across an authenticated request.
///
/// `AuthRepository` provides the concrete implementation; the bookmark, smart-view, and sync layers
/// depend on this narrow protocol so they can make authenticated requests without owning the auth
/// state. The returned `AuthorizedClient` refreshes the token before the request when it is expiring
/// soon, and — if the server rejects an apparently-valid token — forces one refresh and retries once.
/// Refreshes are coalesced onto a single in-flight task, and the session is logged out only on a
/// definitive authentication failure; any other error is rethrown with the session intact.
@MainActor
protocol SessionRefreshing: AnyObject {

    func authorizedClient() async throws -> AuthorizedClient
}
