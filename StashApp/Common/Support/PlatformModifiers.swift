// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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

    /// A whole-number entry field (e.g. a relative-age duration amount): number-pad keyboard on iOS.
    func numberFieldStyle() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
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

    /// Outer chrome for a Settings tab's content: macOS pads it inside the settings window so it
    /// doesn't sit flush against the edges (matching the General and Account tabs); iOS, where the
    /// same view is a pushed screen, lets the grouped `Form`/`List` provide its own insets.
    func settingsChromeStyle() -> some View {
        #if os(macOS)
            padding()
        #else
            self
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

    /// Makes a bookmark row draggable (for dropping onto a sidebar tag) only when `enabled`, keeping
    /// the row's identity stable either way. Disabled on iPhone, where the tags live in a separate tab
    /// so there is no drop target and the lift would compete with the row's long-press context menu.
    @ViewBuilder
    func draggableBookmark(_ bookmark: Bookmark, enabled: Bool) -> some View {
        if enabled {
            draggable(bookmark)
        } else {
            self
        }
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
