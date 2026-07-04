// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import SwiftUI

// MARK: - MetadataFaviconView

/// The favicon shown in the shared add-bookmark form's metadata preview. A `Common` sibling of the
/// app's `FaviconView`: it must compile into the Share Extension too, where the app-only `AppSettings`
/// is unavailable, so it reads the configured server URL straight from the App Group's shared
/// `UserDefaults` (the same value `AppSettings` writes through). Shares the `roundedFavicon` styling
/// and `FaviconMonogram` fallback so it looks identical to the list/detail favicons.
struct MetadataFaviconView: View {

    // MARK: Properties

    private let domain: String?
    private let size: CGFloat

    // MARK: Computed Properties

    private var iconURL: URL? {
        let base = AppGroup.makeSharedDefaults().string(forKey: AppGroup.serverURLKey) ?? ""

        return .stashFavicon(base: base, domain: domain)
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
        MetadataFaviconView(domain: "swift.org", size: 24)
            .padding()
    }
#endif
