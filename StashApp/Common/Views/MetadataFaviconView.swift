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
