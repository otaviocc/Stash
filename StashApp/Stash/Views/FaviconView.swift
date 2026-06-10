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

/// A view that displays a favicon for a given URL.
struct FaviconView: View {

    // MARK: Properties

    private let iconURL: URL?

    // MARK: Lifecycle

    init(url: URL?) {
        iconURL = url.flatMap {
            URL(string: "https://www.google.com/s2/favicons?sz=16&domain=\($0.absoluteString)")
        }
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        AsyncImage(url: iconURL) { image in
            image
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
        FaviconView(url: URL(string: "https://swift.org"))
            .padding()
    }
#endif
