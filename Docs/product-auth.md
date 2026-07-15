# Stash PRD: Authentication & Security (§8)

_Part of the Stash Product Requirements Document. See [`PRODUCT.md`](../PRODUCT.md) for the index._

---

## 8. Authentication & Security

### 8.1 Token Strategy

| Token | Lifetime | Storage (client) |
|-------|----------|-----------------|
| Access token (JWT, HS256) | 15 minutes | Keychain (iOS/macOS), memory (CLI, web) |
| Refresh token (opaque 256-bit hex) | 90 days, rotated on use | Keychain (iOS/macOS), file (CLI), session (web) |

Silent refresh within 60 seconds of expiry. The 2FA temp token uses `scope:
"2fa"` so it cannot be replayed as an access token.

One deviation from my original plan: both tokens live in Keychain on
iOS/macOS, not just the refresh token; that's what makes cold-start session
restoration and Share Extension token reuse possible.

### 8.2 Login Flow

```
POST /api/v1/auth/login  { username, password }
→ 2FA disabled: { accessToken, refreshToken }
→ 2FA enabled:  { requires2FA: true, tempToken }

POST /api/v1/auth/totp   { tempToken, totpCode }
→ { accessToken, refreshToken }

POST /api/v1/auth/recovery  { tempToken, recoveryCode }
→ { accessToken, refreshToken }  (code marked used)

POST /api/v1/auth/refresh { refreshToken }
→ { accessToken, refreshToken }  (old token deleted)

POST /api/v1/auth/logout  { refreshToken }
→ 204 No Content
```

### 8.3 2FA Enrollment

```
GET  /api/v1/auth/totp/setup
→ { secret, otpauthURI }

POST /api/v1/auth/totp/verify-setup  { totpCode }
→ { recoveryCodes: [...] }  (8 codes, shown once)
```

Recovery codes: 8 × `XXXX-XXXX`, bcrypt-hashed, single-use. Shown exactly once
with mandatory "I've saved these" confirmation.

The web UI shows the `otpauthURI` plus a manual setup key, no QR image, since
CoreImage isn't available on Linux. The native clients render a QR code from
`otpauthURI` instead.

### 8.4 2FA Disable / Reset

**User self-service (`POST /api/v1/auth/totp/disable`):** requires current TOTP
code. Clears `totpSecret`, sets `isTOTPEnabled = false`, deletes recovery codes,
invalidates all refresh tokens.

**Admin reset (`POST /api/v1/admin/users/:id/reset-totp`):** no confirmation
code required. Same effect. Self-reset allowed. Invalidates refresh tokens.

### 8.5 Password Rules

Minimum 12 characters. Bcrypt, cost factor 12. Unknown usernames run a throwaway
bcrypt verify to prevent timing-based account enumeration.

### 8.6 Token Invalidation Rules

All refresh tokens for a user are deleted when:
- Account suspended
- Password reset by admin
- Account hard-deleted
- 2FA disabled (self-service or admin reset)

---
