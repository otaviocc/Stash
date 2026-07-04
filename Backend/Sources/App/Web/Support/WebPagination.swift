// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// The fixed page size and page-count arithmetic for the web frontend's paginated lists (the
/// bookmark list and Smart View results), so the two pages can't drift.
enum WebPagination {

    // MARK: Static Properties

    static let perPage = 20

    // MARK: Static Functions

    static func pageCount(total: Int) -> Int {
        total == 0 ? 1 : (total + perPage - 1) / perPage
    }
}
