// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - UserDTO

/// A user account as returned by the API.
public struct UserDTO: Codable, Identifiable, Sendable {

    // MARK: Nested Types

    private enum CodingKeys: String, CodingKey {

        case id
        case username
        case role
        case isActive
        case isTOTPEnabled
        case bookmarkCount
        case archiveNewBookmarks
        case createdAt
    }

    // MARK: Properties

    public let id: UUID
    public let username: String
    public let role: UserRoleDTO
    public let isActive: Bool
    public let isTOTPEnabled: Bool
    public let bookmarkCount: Int
    public let archiveNewBookmarks: Bool
    public let createdAt: Date

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        role = try container.decode(UserRoleDTO.self, forKey: .role)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isTOTPEnabled = try container.decode(Bool.self, forKey: .isTOTPEnabled)
        bookmarkCount = try container.decode(Int.self, forKey: .bookmarkCount)
        archiveNewBookmarks = try container.decodeIfPresent(Bool.self, forKey: .archiveNewBookmarks) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
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
