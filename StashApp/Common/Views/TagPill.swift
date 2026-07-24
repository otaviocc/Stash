// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - TagPill

/// A label for a tag, rendering the hierarchical `swift/server` source as a `swift › server` display.
/// Shared by the bookmark rows, the detail view, and the add/edit tag summary so a tag reads the same
/// everywhere. The default styled capsule suits the detail and form summaries; the `isPlain` variant
/// drops the background to a quiet, text-only treatment for the content-first list row.
struct TagPill: View {

    // MARK: SwiftUI Properties

    @Environment(\.instanceAccent) private var instanceAccent

    // MARK: Properties

    let name: String
    var isPlain = false

    // MARK: Computed Properties

    private var displayName: String {
        name.tagDisplayName
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        if isPlain {
            Text(displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(displayName)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(instanceAccent.opacity(0.15), in: .capsule)
                .foregroundStyle(instanceAccent)
        }
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 16) {
            HStack {
                TagPill(name: "swift")
                TagPill(name: "swift/server")
            }

            HStack {
                TagPill(name: "swift", isPlain: true)
                TagPill(name: "swift/server", isPlain: true)
            }
        }
        .padding()
    }
#endif
