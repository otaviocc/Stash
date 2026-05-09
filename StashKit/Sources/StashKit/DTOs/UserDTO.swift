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

// MARK: - UserDTO

/// A user account as returned by the API.
public struct UserDTO: Codable, Identifiable, Sendable {

    public let id: UUID
    public let username: String
    public let role: UserRoleDTO
    public let isActive: Bool
    public let isTOTPEnabled: Bool
    public let bookmarkCount: Int
    public let createdAt: Date
}

// MARK: - UserRoleDTO

/// The role of a user account.
public enum UserRoleDTO: String, Codable, Sendable {

    case admin
    case user
}

// MARK: - AdminStatsDTO

/// Aggregate admin statistics.
public struct AdminStatsDTO: Codable, Sendable {

    public let totalUsers: Int
    public let totalBookmarks: Int
    public let users: [UserStatDTO]
}

// MARK: - UserStatDTO

/// Per-user statistics for the admin dashboard.
public struct UserStatDTO: Codable, Sendable {

    public let id: UUID
    public let username: String
    public let bookmarkCount: Int
    public let isActive: Bool
}
