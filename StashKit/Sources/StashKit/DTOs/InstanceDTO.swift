// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

import Foundation

// MARK: - InstanceDTO

/// Public instance chrome returned by `GET /api/v1/instance`, currently just the accent theme.
public struct InstanceDTO: Codable, Sendable {

    public let accent: AccentDTO
}

// MARK: - AccentDTO

/// The instance's accent theme: an identifier plus its resolved light-mode and dark-mode hex.
public struct AccentDTO: Codable, Sendable {

    public let theme: String
    public let light: String
    public let dark: String
}
