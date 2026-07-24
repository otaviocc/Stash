// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation
import StashKit

// MARK: - InstanceRepository

/// Fetches the instance's accent theme from `GET /api/v1/instance`. The endpoint is
/// unauthenticated, so this talks to the plain `StashClient` directly rather than going through
/// `AuthRepository.authorizedClient()` — the accent should be available even before login (e.g. so
/// the login screen itself can tint).
@MainActor
final class InstanceRepository {

    // MARK: Properties

    private let clientProvider: StashClientProvider

    // MARK: Lifecycle

    init(
        clientProvider: StashClientProvider
    ) {
        self.clientProvider = clientProvider
    }

    // MARK: Functions

    /// Fetches the current instance accent, or `nil` on any failure (no server configured, offline,
    /// unreachable). Fails soft: the caller keeps whatever accent it already has cached rather than
    /// falling back to the built-in default on a transient error.
    func fetchAccent() async -> InstanceAccent? {
        guard let client = clientProvider.client(),
              let dto = try? await client.run(InstanceRequestFactory.makeInstanceRequest()).value
        else {
            return nil
        }

        return .init(theme: dto.accent.theme, light: dto.accent.light, dark: dto.accent.dark)
    }
}
