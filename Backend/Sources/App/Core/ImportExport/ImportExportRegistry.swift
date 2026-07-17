// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Central registry of importers and exporters. To support a new format, conform a type to
/// `BookmarkImporter`/`BookmarkExporter` and add a `register(...)` line in `init()` below — the
/// web UI's format selectors and the import/export routes pick it up automatically.
///
/// Registration happens once during `init`; the registry is immutable thereafter, so concurrent
/// reads from request handlers are safe.
final class ImportExportRegistry: @unchecked Sendable {

    // MARK: Static Properties

    static let shared = ImportExportRegistry()

    // MARK: Properties

    private var importers: [String: any BookmarkImporter] = [:]
    private var exporters: [String: any BookmarkExporter] = [:]

    // MARK: Computed Properties

    var importerOptions: [FormatOption] {
        importers.values
            .map { FormatOption(identifier: type(of: $0).identifier, displayName: type(of: $0).displayName) }
            .sorted { $0.displayName < $1.displayName }
    }

    var exporterOptions: [FormatOption] {
        exporters.values
            .map { FormatOption(identifier: type(of: $0).identifier, displayName: type(of: $0).displayName) }
            .sorted { $0.displayName < $1.displayName }
    }

    // MARK: Lifecycle

    private init() {
        register(importer: AnyboxImporter())
        register(importer: StashJSONImporter())
        register(exporter: StashJSONExporter())
        register(exporter: AnyboxExporter())
    }

    // MARK: Functions

    func importer(for identifier: String) -> (any BookmarkImporter)? {
        importers[identifier]
    }

    func exporter(for identifier: String) -> (any BookmarkExporter)? {
        exporters[identifier]
    }

    private func register(importer: any BookmarkImporter) {
        importers[type(of: importer).identifier] = importer
    }

    private func register(exporter: any BookmarkExporter) {
        exporters[type(of: exporter).identifier] = exporter
    }
}
