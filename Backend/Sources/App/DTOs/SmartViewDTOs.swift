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

import Vapor

// MARK: - SmartViewConditionPayload

/// A single Smart View condition on the wire — a `{ type, value }` pair, both strings.
struct SmartViewConditionPayload: Content {

    let type: String
    let value: String
}

// MARK: - SmartViewRequestBody

/// `POST` / `PUT /smart-views` body — the display name, the match mode (`all` / `any`), and the
/// (unvalidated) condition list. `matchMode` is optional: omitting it defaults to `all` on create
/// and leaves the existing value unchanged on update.
struct SmartViewRequestBody: Content {

    // MARK: Properties

    let name: String
    let matchMode: String?
    let conditions: [SmartViewConditionPayload]

    // MARK: Lifecycle

    init(name: String, conditions: [SmartViewConditionPayload], matchMode: String? = nil) {
        self.name = name
        self.matchMode = matchMode
        self.conditions = conditions
    }
}

// MARK: - SmartViewResponse

/// Public Smart View projection returned by the API.
struct SmartViewResponse: Content {

    let id: UUID
    let name: String
    let matchMode: String
    let conditions: [SmartViewConditionPayload]
    let createdAt: Date
    let updatedAt: Date
}
