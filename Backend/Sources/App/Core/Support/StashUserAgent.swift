// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

// MARK: - StashUserAgent

/// The `User-Agent` sent on every outbound HTTP request Stash makes on a user's behalf (metadata
/// fetching, favicon fetching, Internet Archive submission), so a single string identifies the
/// requester across all of them.
enum StashUserAgent {

    static let value = "StashBot/1.0 (+https://github.com/\(StashRepo.path))"
}

// MARK: - StashRepo

/// This project's GitHub repository identity: the single source of truth for anywhere Stash
/// needs to reference its own repo (the User-Agent backlink above, `UpdateChecker`'s GitHub
/// Releases API call), so a rename or org transfer only needs one edit.
enum StashRepo {

    static let path = "otaviocc/Stash"
}
