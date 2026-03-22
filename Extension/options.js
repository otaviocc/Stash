// Stash settings page. Drives sign-in (including the 2FA branch) by talking to
// the background service worker over chrome.runtime.sendMessage; it never
// touches token storage directly.

const loginForm = document.getElementById("login-form");
const totpForm = document.getElementById("totp-form");

const serverInput = document.getElementById("server-url");
const usernameInput = document.getElementById("username");
const passwordInput = document.getElementById("password");

const saveButton = document.getElementById("save");
const signoutButton = document.getElementById("signout");
const verifyButton = document.getElementById("verify");
const toggleRecovery = document.getElementById("toggle-recovery");

const statusEl = document.getElementById("status");
const errorEl = document.getElementById("error");
const totpError = document.getElementById("totp-error");
const totpHint = document.getElementById("totp-hint");
const totpLabel = document.getElementById("totp-label");
const totpCode = document.getElementById("totp-code");

let pendingTempToken = null;
let recoveryMode = false;

function send(message) {
  return chrome.runtime.sendMessage(message);
}

function show(el, text) {
  el.textContent = text;
  el.hidden = false;
}

function hide(el) {
  el.hidden = true;
}

function setStatus(text, kind) {
  statusEl.className = `status ${kind}`;
  show(statusEl, text);
}

async function refreshStatus() {
  const status = await send({ action: "getStatus" });

  if (status.serverURL) {
    serverInput.value = status.serverURL;
  }
  if (status.username) {
    usernameInput.value = status.username;
  }

  if (status.signedIn) {
    setStatus(`Connected as ${status.username || "your account"}`, "ok");
    signoutButton.hidden = false;
  } else {
    setStatus("Not signed in", "off");
    signoutButton.hidden = true;
  }
}

function showTOTP() {
  loginForm.hidden = true;
  totpForm.hidden = false;
  hide(totpError);
  totpCode.value = "";
  totpCode.focus();
}

function showLogin() {
  totpForm.hidden = true;
  loginForm.hidden = false;
  pendingTempToken = null;
  recoveryMode = false;
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  hide(errorEl);
  saveButton.disabled = true;
  saveButton.textContent = "Signing in…";

  const result = await send({
    action: "login",
    serverURL: serverInput.value.trim(),
    username: usernameInput.value.trim(),
    password: passwordInput.value
  });

  saveButton.disabled = false;
  saveButton.textContent = "Save & Sign In";

  if (result.requires2FA) {
    pendingTempToken = result.tempToken;
    showTOTP();
    return;
  }

  if (result.ok) {
    passwordInput.value = "";
    await refreshStatus();
  } else {
    show(errorEl, result.error);
  }
});

totpForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  hide(totpError);
  verifyButton.disabled = true;
  verifyButton.textContent = "Verifying…";

  const result = await send({
    action: "verify2FA",
    tempToken: pendingTempToken,
    code: totpCode.value.trim(),
    mode: recoveryMode ? "recovery" : "totp"
  });

  verifyButton.disabled = false;
  verifyButton.textContent = "Verify";

  if (result.ok) {
    passwordInput.value = "";
    showLogin();
    await refreshStatus();
  } else {
    show(totpError, result.error);
  }
});

toggleRecovery.addEventListener("click", () => {
  recoveryMode = !recoveryMode;
  hide(totpError);
  totpCode.value = "";

  if (recoveryMode) {
    totpHint.textContent = "Enter one of your single-use recovery codes.";
    totpLabel.textContent = "Recovery code";
    totpCode.placeholder = "XXXX-XXXX";
    totpCode.setAttribute("autocomplete", "off");
    toggleRecovery.textContent = "Use an authenticator code";
  } else {
    totpHint.textContent = "Enter the 6-digit code from your authenticator app.";
    totpLabel.textContent = "Verification code";
    totpCode.placeholder = "123456";
    totpCode.setAttribute("autocomplete", "one-time-code");
    toggleRecovery.textContent = "Use a recovery code";
  }

  totpCode.focus();
});

signoutButton.addEventListener("click", async () => {
  await send({ action: "logout" });
  passwordInput.value = "";
  showLogin();
  await refreshStatus();
});

refreshStatus();
