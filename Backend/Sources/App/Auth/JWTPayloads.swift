import JWT
import Vapor

/// Short-lived access token (15 minutes). PRD §8.1.
struct AccessTokenPayload: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case scope
        case role
    }

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    /// Marks the token kind so a temp/2FA token can never be used as an access token.
    var scope: String
    var role: String

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard scope == AccessTokenPayload.scopeValue else {
            throw JWTError.claimVerificationFailure(name: "scope", reason: "not an access token")
        }
    }

    static let scopeValue = "access"

    var userID: UUID? { UUID(uuidString: subject.value) }

    init(user: User, lifetime: TimeInterval = 15 * 60) throws {
        self.subject = SubjectClaim(value: try user.requireID().uuidString)
        self.expiration = ExpirationClaim(value: Date().addingTimeInterval(lifetime))
        self.scope = AccessTokenPayload.scopeValue
        self.role = user.role.rawValue
    }
}

/// Limited-scope temporary token issued between password login and the 2FA step (5 minutes). PRD §8.2.
struct TempTokenPayload: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case scope
    }

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var scope: String

    func verify(using signer: JWTSigner) throws {
        try expiration.verifyNotExpired()
        guard scope == TempTokenPayload.scopeValue else {
            throw JWTError.claimVerificationFailure(name: "scope", reason: "not a 2FA temp token")
        }
    }

    static let scopeValue = "2fa"

    var userID: UUID? { UUID(uuidString: subject.value) }

    init(user: User, lifetime: TimeInterval = 5 * 60) throws {
        self.subject = SubjectClaim(value: try user.requireID().uuidString)
        self.expiration = ExpirationClaim(value: Date().addingTimeInterval(lifetime))
        self.scope = TempTokenPayload.scopeValue
    }
}
