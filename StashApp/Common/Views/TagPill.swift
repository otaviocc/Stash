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

// MARK: - TagPill

/// A small capsule label for a tag. Shared by the bookmark rows, the detail view, and the add/edit
/// tag summary so a tag reads the same everywhere.
struct TagPill: View {

    // MARK: Properties

    let name: String

    // MARK: Computed Properties

    private var displayName: String {
        name.components(separatedBy: "/").joined(separator: " › ")
    }

    // MARK: Content Properties

    // MARK: Content

    var body: some View {
        Text(displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: .capsule)
            .foregroundStyle(Color.accentColor)
    }
}

#if DEBUG
    #Preview {
        HStack {
            TagPill(name: "swift")
            TagPill(name: "swift/server")
        }
        .padding()
    }
#endif
