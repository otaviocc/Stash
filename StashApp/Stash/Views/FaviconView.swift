// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - FaviconView

/// A view that displays a favicon served from the configured Stash instance, keyed by domain.
/// Falls back to a `FaviconMonogram` (the domain's first letter) while loading and when the instance
/// has no cached icon (404).
struct FaviconView: View {

    // MARK: SwiftUI Properties

    @Environment(AppSettings.self) private var appSettings

    // MARK: Properties

    private let domain: String?
    private let size: CGFloat

    // MARK: Computed Properties

    private var iconURL: URL? {
        .stashFavicon(base: appSettings.serverURL, domain: domain)
    }

    // MARK: Lifecycle

    init(domain: String?, size: CGFloat = 18) {
        self.domain = domain
        self.size = size
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        AsyncImage(url: iconURL) { image in
            image
                .resizable()
                .scaledToFit()
                .roundedFavicon(size: size)
        } placeholder: {
            FaviconMonogram(domain: domain, size: size)
        }
    }
}

#if DEBUG
    #Preview {
        FaviconView(domain: "swift.org")
            .environment(AppSettings.preview)
            .padding()
    }
#endif
