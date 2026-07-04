// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation

    extension AppSettings {

        /// Throwaway settings for previews, backed by an isolated suite so previews never touch the
        /// App Group's persisted server URL.
        @MainActor
        static var preview: AppSettings {
            AppSettings(defaults: UserDefaults(suiteName: "preview.com.example.otavio.stash") ?? .standard)
        }
    }
#endif
