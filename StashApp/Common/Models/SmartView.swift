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
import StashKit

// MARK: - SmartView

/// A saved query owned by the user, shown in the sidebars and run live against the bookmarks. The
/// native apps consume Smart Views (browse and open them); creating and editing them is done from the
/// web frontend.
struct SmartView: Identifiable, Hashable {

    let id: UUID
    let name: String
    let matchMode: String
    let conditions: [SmartViewCondition]
}

// MARK: - SmartView + DTO

extension SmartView {

    init(
        dto: SmartViewDTO
    ) {
        id = dto.id
        name = dto.name
        matchMode = dto.matchMode
        conditions = dto.conditions.map(SmartViewCondition.init(dto:))
    }
}

// MARK: - SmartViewCondition

/// One `{ type, value }` rule of a Smart View, kept verbatim from the wire shape.
struct SmartViewCondition: Hashable {

    let type: String
    let value: String
}

// MARK: - SmartViewCondition + DTO

extension SmartViewCondition {

    init(
        dto: SmartViewConditionDTO
    ) {
        type = dto.type
        value = dto.value
    }
}
