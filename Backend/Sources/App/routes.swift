import Fluent
import Vapor

func routes(_ app: Application) throws {
    // Unversioned health check (PRD §17.3).
    app.get("health") { _ in HealthResponse(status: "ok") }

    // All API routes are prefixed /api/v1/ (PRD §17.3).
    let api = app.grouped("api", "v1")

    // Unauthenticated auth endpoints.
    try api.register(collection: AuthController())

    // Authenticated endpoints (any role).
    let protected = api.grouped(
        AccessTokenAuthenticator(),
        User.guardMiddleware(throwing: APIError.tokenInvalid)
    )
    try protected.register(collection: UserController())
}
