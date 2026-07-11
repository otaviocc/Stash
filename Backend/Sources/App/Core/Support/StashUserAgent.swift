// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

/// The `User-Agent` sent on every outbound HTTP request Stash makes on a user's behalf (metadata
/// fetching, favicon fetching, Internet Archive submission), so a single string identifies the
/// requester across all of them.
enum StashUserAgent {

    static let value = "StashBot/1.0 (+https://github.com/otaviocc/stash)"
}
