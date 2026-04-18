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

import SwiftUI

// MARK: - OfflineBanner

/// A slim, informational banner shown at the top of the app shell while the device is offline.
///
/// Muted rather than alarming — being offline is a supported state, and queued changes sync on
/// reconnect. Applied as a `.safeAreaInset(edge: .top)` on the main shells, which animate it in and
/// out as connectivity changes.
struct OfflineBanner: View {

    // MARK: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
            Text("Working offline — changes will sync when reconnected")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(.bar)
    }
}

// MARK: - PendingSyncBadge

/// A small, muted indicator that a bookmark has a local change still waiting to be pushed. Shown in
/// the trailing edge of a row and the detail header; it carries no action — interaction with the
/// bookmark is never blocked — and disappears once the change syncs.
struct PendingSyncBadge: View {

    // MARK: Content

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Waiting to sync")
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 0) {
            OfflineBanner()
            Spacer()
            PendingSyncBadge()
            Spacer()
        }
    }
#endif
