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

// MARK: - FaviconView

/// A view that displays a favicon served from the configured Stash instance, keyed by domain.
/// Falls back to a `link` symbol while loading and when the instance has no cached icon (404).
struct FaviconView: View {

    // MARK: SwiftUI Properties

    @Environment(AppSettings.self) private var appSettings

    // MARK: Properties

    private let domain: String?

    // MARK: Computed Properties

    private var iconURL: URL? {
        guard let domain, !domain.isEmpty else { return nil }

        var base = appSettings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        guard !base.isEmpty else { return nil }

        return URL(string: "\(base)/api/v1/favicons/\(domain)")
    }

    // MARK: Lifecycle

    init(domain: String?) {
        self.domain = domain
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        AsyncImage(url: iconURL) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            Image(systemName: "link")
        }
        .roundedFavicon()
    }
}

// MARK: - RoundFaviconModifier

/// Applies standard favicon styling: fixed 16×16 size with rounded corners.
struct RoundFaviconModifier: ViewModifier {

    func body(content: Content) -> some View {
        content
            .frame(width: 16, height: 16)
            .clipShape(.rect(cornerRadius: 4))
    }
}

// MARK: - View + RoundedFavicon

extension View {

    func roundedFavicon() -> some View {
        modifier(RoundFaviconModifier())
    }
}

#if DEBUG
    #Preview {
        FaviconView(domain: "swift.org")
            .environment(AppSettings.preview)
            .padding()
    }
#endif
