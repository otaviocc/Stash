// Stash browser extension — service worker.
//
// Owns all token storage and every authenticated call to the Stash REST API.
// The popup and options page never touch chrome.storage for tokens directly;
// they talk to this worker over chrome.runtime.sendMessage (see the message API
// at the bottom of this file). Keeping token logic in one place mirrors the way
// the iOS app and CLI centralize silent refresh.

const STORAGE_KEYS = ["serverURL", "accessToken", "refreshToken", "username"];

// Refresh the access token when it is within this many seconds of expiry, the
// same 60-second window the CLI and iOS app use.
const EXPIRY_SKEW_SECONDS = 60;

// --- Storage helpers --------------------------------------------------------

async function getStored() {
  return chrome.storage.local.get(STORAGE_KEYS);
}

async function setStored(values) {
  return chrome.storage.local.set(values);
}

async function clearTokens() {
  return chrome.storage.local.remove(["accessToken", "refreshToken"]);
}

// --- URL + JWT helpers ------------------------------------------------------

function joinURL(serverURL, path) {
  return serverURL.replace(/\/+$/, "") + path;
}

// Decode a JWT's `exp` claim by hand (base64url-decode the payload), the same
// dependency-free approach as the CLI's JWTDecoder and the app's TokenManager.
// Returns the expiry as Unix seconds, or null if the token can't be parsed.
function decodeExp(token) {
  try {
    const payload = token.split(".")[1];
    if (!payload) {
      return null;
    }

    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
    const claims = JSON.parse(atob(padded));

    return typeof claims.exp === "number" ? claims.exp : null;
  } catch (error) {
    return null;
  }
}

function isExpiringSoon(token) {
  const exp = decodeExp(token);
  if (exp === null) {
    return true;
  }

  return exp - Date.now() / 1000 < EXPIRY_SKEW_SECONDS;
}

// --- Auth -------------------------------------------------------------------

class AuthError extends Error {}

async function postJSON(serverURL, path, body) {
  const response = await fetch(joinURL(serverURL, path), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify(body)
  });

  let data = null;
  try {
    data = await response.json();
  } catch (error) {
    data = null;
  }

  return { response, data };
}

// Calls POST /api/v1/auth/login. Returns either a token pair (stored, signed
// in) or the { requires2FA, tempToken } challenge — both arrive as HTTP 200, so
// the shape of the body decides, exactly as in the CLI and app.
async function login(serverURL, username, password) {
  const normalizedURL = serverURL.replace(/\/+$/, "");
  const { response, data } = await postJSON(normalizedURL, "/api/v1/auth/login", {
    username,
    password
  });

  if (!response.ok) {
    throw new AuthError((data && data.message) || "Sign in failed.");
  }

  if (data && data.requires2FA) {
    await setStored({ serverURL: normalizedURL });
    return { requires2FA: true, tempToken: data.tempToken };
  }

  await persistSession(normalizedURL, username, data);
  return { signedIn: true, username };
}

// Completes a 2FA login with either a TOTP code or a recovery code.
async function verify2FA(tempToken, code, mode) {
  const { serverURL } = await getStored();
  if (!serverURL) {
    throw new AuthError("Stash is not configured.");
  }

  const path = mode === "recovery" ? "/api/v1/auth/recovery" : "/api/v1/auth/totp";
  const body =
    mode === "recovery"
      ? { tempToken, recoveryCode: code }
      : { tempToken, totpCode: code };

  const { response, data } = await postJSON(serverURL, path, body);
  if (!response.ok) {
    throw new AuthError((data && data.message) || "Invalid code.");
  }

  await persistSession(serverURL, null, data);
  const username = await resolveUsername(serverURL, data.accessToken);
  return { signedIn: true, username };
}

async function persistSession(serverURL, username, pair) {
  if (!pair || !pair.accessToken || !pair.refreshToken) {
    throw new AuthError("The server returned an unexpected response.");
  }

  const values = {
    serverURL,
    accessToken: pair.accessToken,
    refreshToken: pair.refreshToken
  };
  if (username) {
    values.username = username;
  }

  await setStored(values);
}

// Looks up the signed-in user's name via GET /api/v1/me so the status line can
// show it even after a 2FA login (where the username wasn't entered locally).
async function resolveUsername(serverURL, accessToken) {
  try {
    const response = await fetch(joinURL(serverURL, "/api/v1/me"), {
      headers: { Authorization: `Bearer ${accessToken}`, Accept: "application/json" }
    });
    if (!response.ok) {
      return null;
    }

    const user = await response.json();
    if (user && user.username) {
      await setStored({ username: user.username });
      return user.username;
    }
  } catch (error) {
    // Non-fatal: the session is valid even if the name can't be fetched.
  }

  return null;
}

// Rotates the stored token pair via POST /api/v1/auth/refresh.
async function refreshTokens() {
  const { serverURL, refreshToken } = await getStored();
  if (!serverURL || !refreshToken) {
    throw new AuthError("Not signed in.");
  }

  const { response, data } = await postJSON(serverURL, "/api/v1/auth/refresh", {
    refreshToken
  });

  if (!response.ok) {
    await clearTokens();
    throw new AuthError("Session expired. Sign in again.");
  }

  await persistSession(serverURL, null, data);
  return data.accessToken;
}

// Returns a valid access token, refreshing silently if it is missing or within
// the expiry skew. Throws if the extension isn't configured or signed in.
async function getAccessToken() {
  const { serverURL, accessToken, refreshToken } = await getStored();
  if (!serverURL) {
    throw new AuthError("Stash is not configured.");
  }
  if (!accessToken && !refreshToken) {
    throw new AuthError("Not signed in.");
  }

  if (!accessToken || isExpiringSoon(accessToken)) {
    return refreshTokens();
  }

  return accessToken;
}

async function logout() {
  const { serverURL, refreshToken } = await getStored();
  if (serverURL && refreshToken) {
    try {
      await postJSON(serverURL, "/api/v1/auth/logout", { refreshToken });
    } catch (error) {
      // Best-effort: clear locally even if the server can't be reached.
    }
  }

  await clearTokens();
}

// --- Authenticated API wrapper ---------------------------------------------

// Authenticated fetch against the configured Stash instance. Prepends the
// server URL, attaches a fresh Bearer token, and on a 401 attempts exactly one
// silent refresh + retry before clearing the session.
async function callAPI(method, path, body) {
  const { serverURL } = await getStored();
  if (!serverURL) {
    throw new AuthError("Stash is not configured.");
  }

  const send = async (token) => {
    const init = {
      method,
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" }
    };
    if (body !== undefined && body !== null) {
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }

    return fetch(joinURL(serverURL, path), init);
  };

  let token = await getAccessToken();
  let response = await send(token);

  if (response.status === 401) {
    token = await refreshTokens();
    response = await send(token);
    if (response.status === 401) {
      await clearTokens();
    }
  }

  if (response.status === 204) {
    return { ok: true, data: null };
  }

  let data = null;
  try {
    data = await response.json();
  } catch (error) {
    data = null;
  }

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      error: (data && data.message) || `Request failed (${response.status}).`,
      code: data && data.code,
      existingID: data && data.existingID
    };
  }

  return { ok: true, data };
}

// --- Message API ------------------------------------------------------------

async function getStatus() {
  const { serverURL, refreshToken, username } = await getStored();
  return {
    configured: Boolean(serverURL),
    signedIn: Boolean(serverURL && refreshToken),
    username: username || null,
    serverURL: serverURL || null
  };
}

async function handleMessage(message) {
  switch (message.action) {
    case "login":
      try {
        const result = await login(message.serverURL, message.username, message.password);
        if (result.requires2FA) {
          return { requires2FA: true, tempToken: result.tempToken };
        }

        return { ok: true, username: result.username };
      } catch (error) {
        return { ok: false, error: messageFor(error) };
      }

    case "verify2FA":
      try {
        const result = await verify2FA(message.tempToken, message.code, message.mode);
        return { ok: true, username: result.username };
      } catch (error) {
        return { ok: false, error: messageFor(error) };
      }

    case "logout":
      await logout();
      return { ok: true };

    case "getStatus":
      return getStatus();

    case "apiCall":
      try {
        return await callAPI(message.method, message.path, message.body);
      } catch (error) {
        return { ok: false, error: messageFor(error) };
      }

    default:
      return { ok: false, error: "Unknown action." };
  }
}

function messageFor(error) {
  if (error instanceof AuthError) {
    return error.message;
  }

  return "Could not reach your Stash instance. Check your connection and settings.";
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message).then(sendResponse);
  return true;
});
