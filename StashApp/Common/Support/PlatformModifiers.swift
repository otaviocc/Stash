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
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Copies a string to the system pasteboard on either platform. SwiftUI has no cross-platform copy
/// API, so this is the one place the per-platform pasteboard types are touched.
func copyToPasteboard(_ string: String) {
    #if os(iOS)
        UIPasteboard.general.string = string
    #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    #endif
}

/// Cross-platform text-field and navigation adornments.
///
/// SwiftUI's keyboard, autocapitalization, content-type, and inline-title-display modifiers are
/// iOS-only; this file concentrates the `#if os(iOS)` branches in one place so the shared views read
/// as plain SwiftUI and the macOS target compiles without scattering platform checks. On macOS these
/// hints are unnecessary (there is no software keyboard), so each helper simply applies the
/// platform-neutral remainder (`autocorrectionDisabled()` where it adds value, otherwise nothing).
extension View {

    /// A URL entry field: no autocapitalization or autocorrection, URL keyboard and content type.
    func urlFieldStyle() -> some View {
        #if os(iOS)
            textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// A username entry field: no autocapitalization or autocorrection.
    func usernameFieldStyle() -> some View {
        #if os(iOS)
            textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// A password entry field.
    func passwordFieldStyle() -> some View {
        #if os(iOS)
            textContentType(.password)
        #else
            self
        #endif
    }

    /// A numeric one-time-code entry field (six-digit TOTP).
    func oneTimeCodeFieldStyle() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        #else
            self
        #endif
    }

    /// A lowercase-preserving field: no autocapitalization or autocorrection. Used for search and
    /// comma-separated tag input.
    func lowercasedFieldStyle() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// An uppercase-preferring field (recovery codes): characters capitalization, no autocorrection.
    func uppercasedFieldStyle() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// Applies the inline navigation-title display mode on iOS; a no-op on macOS, which has no
    /// large-title concept.
    func inlineNavigationTitleStyle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }

    /// A search field: no autocapitalization or autocorrection so the query is sent as typed.
    func searchInputStyle() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// Renders a `Button` inside a grouped `Form` as a full-width, borderless, tinted row on macOS so
    /// it matches a `Link` row (and iOS's automatic row styling) instead of getting the default
    /// bordered push-button chrome. A no-op on iOS, where the grouped form already renders buttons
    /// this way. Pass `isDestructive: true` to tint the row red, matching a destructive `Link`/role.
    func formButtonRowStyle(isDestructive: Bool = false) -> some View {
        #if os(macOS)
            buttonStyle(.plain)
                .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(Color.accentColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        #else
            self
        #endif
    }
}
