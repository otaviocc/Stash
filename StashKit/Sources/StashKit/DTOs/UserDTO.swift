// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

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
