// Copyright (C) 2026 Otávio C.
// SPDX-License-Identifier: AGPL-3.0-only

import Vapor

extension Request {

    /// Renders a Leaf template to a full `Response` with an explicit status. The web controllers need
    /// non-200 statuses (validation errors re-render the form as `422`/`400`), which `req.view.render`
    /// alone can't express — it always implies `200`. Shared by every server-rendered web controller.
    func renderHTML(
        _ template: String,
        _ context: some Encodable,
        status: HTTPResponseStatus = .ok
    ) async throws -> Response {
        let view: View = try await view.render(template, context)
        let response = Response(status: status)
        response.headers.contentType = .html
        response.body = .init(buffer: view.data)
        return response
    }

    /// Reads a single HTML checkbox posted under `name`, defaulting to `false`. An unchecked
    /// checkbox is omitted from the form entirely, so a form whose *only* field is that checkbox
    /// submits a genuinely empty body — which `Content.decode` rejects outright with a `422`
    /// before any decoding happens, regardless of how permissive the target type is. Checking the
    /// body's byte count first sidesteps that: an empty body means "unchecked", same as a body
    /// that decodes but is missing the key.
    func decodedCheckbox(named name: String) throws -> Bool {
        guard let data = body.data, data.readableBytes > 0 else {
            return false
        }

        return try content.get(Bool?.self, at: name) ?? false
    }
}
