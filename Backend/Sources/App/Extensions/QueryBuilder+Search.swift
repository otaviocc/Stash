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

import Fluent
import FluentSQL
import SQLKit

// MARK: - QueryBuilder + BookmarkSearch

extension QueryBuilder where Model == Bookmark {

    /// Adds a case-insensitive `OR` group matching `term` against the URL, title, description, and
    /// derived tag-search column.
    ///
    /// Matching is case-insensitive and portable across SQLite (tests) and PostgreSQL (production):
    /// both the column and the term are lowered before a `LIKE` comparison. PostgreSQL's `LIKE` is
    /// otherwise case-sensitive, which the PRD's full-text search (§9.3, "ILIKE on PostgreSQL") does
    /// not want. The term is passed as a bound parameter, so `LIKE` wildcards in the term are treated
    /// as wildcards exactly as the previous `~~` behavior did.
    @discardableResult
    func filterFullText(_ term: String) -> Self {
        let pattern = "%\(term.lowercased())%"

        return group(.or) { group in
            for column in ["url", "title", "description", "tags_search"] {
                group.filter(
                    .sql(
                        SQLBinaryExpression(
                            left: SQLFunction("lower", args: SQLColumn(column)),
                            op: SQLBinaryOperator.like,
                            right: SQLBind(pattern)
                        )
                    )
                )
            }
        }
    }
}
