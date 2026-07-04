// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

#if DEBUG
    import Foundation

    extension AppEnvironment {

        /// A throwaway dependency graph for previews. The real objects are built (nothing hits the
        /// network at init); any auto-load fails fast to an empty state since no server is configured.
        @MainActor
        static var preview: AppEnvironment {
            let environment = AppEnvironment(
                defaults: UserDefaults(suiteName: "preview.com.example.otavio.stash") ?? .standard,
                inMemory: true
            )
            environment.seedPreviewData(Bookmark.samples)

            return environment
        }
    }
#endif
