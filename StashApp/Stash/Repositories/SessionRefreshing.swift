// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

/// A session that vends a client which keeps the access token fresh across an authenticated request.
///
/// `AuthRepository` provides the concrete implementation; the bookmark, smart-view, and sync layers
/// depend on this narrow protocol so they can make authenticated requests without owning the auth
/// state. The returned `AuthorizedClient` refreshes the token before the request when it is expiring
/// soon, and, if the server rejects an apparently-valid token, forces one refresh and retries once.
/// Refreshes are coalesced onto a single in-flight task, and the session is logged out only on a
/// definitive authentication failure; any other error is rethrown with the session intact.
@MainActor
protocol SessionRefreshing: AnyObject {

    func authorizedClient() async throws -> AuthorizedClient
}
