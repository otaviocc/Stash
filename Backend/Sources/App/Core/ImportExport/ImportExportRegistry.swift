// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Central registry of importers and exporters. To support a new format, conform a type to
/// `BookmarkImporter`/`BookmarkExporter` and add a `register(...)` line in `init()` below: the
/// web UI's format selectors and the import/export routes pick it up automatically. To make a
/// format the default preselected in the web UI, update `defaultImporterIdentifier`/
/// `defaultExporterIdentifier` below; that's the one place callers need to consult.
///
/// Registration happens once during `init`; the registry is immutable thereafter, so concurrent
/// reads from request handlers are safe.
final class ImportExportRegistry: @unchecked Sendable {

    // MARK: Static Properties

    static let shared = ImportExportRegistry()

    /// The format preselected in the web UI's import selector. Stash JSON is the lossless,
    /// round-trippable format, so it's the sensible default.
    static let defaultImporterIdentifier = StashJSONImporter.identifier

    /// The format preselected in the web UI's export selector. Stash JSON is the lossless,
    /// round-trippable format, so it's the sensible default.
    static let defaultExporterIdentifier = StashJSONExporter.identifier

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
        register(importer: NetscapeHTMLImporter())
        register(importer: RaindropCSVImporter())
        register(importer: PinboardJSONImporter())
        register(exporter: StashJSONExporter())
        register(exporter: AnyboxExporter())
        register(exporter: NetscapeHTMLExporter())
        register(exporter: RaindropCSVExporter())
        register(exporter: PinboardJSONExporter())
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
