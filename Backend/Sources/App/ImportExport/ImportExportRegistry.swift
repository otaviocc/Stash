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

    /// Format options for the import selector, sorted by display name.
    var importerOptions: [FormatOption] {
        importers.values
            .map { FormatOption(identifier: type(of: $0).identifier, displayName: type(of: $0).displayName) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Format options for the export selector, sorted by display name.
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
