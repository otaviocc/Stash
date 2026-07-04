// Copyright (c) 2026 Otávio C.
// SPDX-License-Identifier: MIT

// Stash popup. Reads the current tab, presents the add-bookmark form, and saves
// via the background service worker. All Stash API calls go through
// { action: "apiCall" }; the popup never touches token storage.

const states = {
  setup: document.getElementById("state-setup"),
  form: document.getElementById("state-form"),
  saved: document.getElementById("state-saved")
};

const setupMessage = document.getElementById("setup-message");
const faviconEl = document.getElementById("favicon");
const urlInput = document.getElementById("url");
const openUrl = document.getElementById("open-url");
const titleInput = document.getElementById("title");
const descriptionInput = document.getElementById("description");
const tagsInput = document.getElementById("tags");
const suggestionsEl = document.getElementById("suggestions");
const formError = document.getElementById("form-error");
const fetchButton = document.getElementById("fetch");
const saveButton = document.getElementById("save");
const savedTitle = document.getElementById("saved-title");
const savedTags = document.getElementById("saved-tags");

let serverURL = null;
let knownTags = [];
let autoCloseTimer = null;

function send(message) {
  return chrome.runtime.sendMessage(message);
}

function showState(name) {
  for (const [key, el] of Object.entries(states)) {
    el.hidden = key !== name;
  }
}

function showError(el, html) {
  el.innerHTML = html;
  el.hidden = false;
}

function hide(el) {
  el.hidden = true;
}

function escapeHTML(value) {
  const div = document.createElement("div");
  div.textContent = value;
  return div.innerHTML;
}

// --- Tag parsing + autocomplete --------------------------------------------

function parseTags(value) {
  return value
    .split(",")
    .map((tag) => tag.trim())
    .filter((tag) => tag.length > 0);
}

// Matches the web UI: a fragment matches any "/"-delimited segment of a known
// tag that starts with it (so "music" finds "kind/music-gear").
function matchesFragment(tag, fragment) {
  const lower = fragment.toLowerCase();
  return tag
    .toLowerCase()
    .split("/")
    .some((segment) => segment.startsWith(lower));
}

function currentFragment() {
  const parts = tagsInput.value.split(",");
  return parts[parts.length - 1].trim();
}

function renderSuggestions() {
  suggestionsEl.innerHTML = "";
  const fragment = currentFragment();
  if (!fragment) {
    return;
  }

  const chosen = new Set(parseTags(tagsInput.value).map((tag) => tag.toLowerCase()));
  const matches = knownTags
    .filter((tag) => matchesFragment(tag, fragment) && !chosen.has(tag.toLowerCase()))
    .slice(0, 6);

  for (const tag of matches) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.textContent = tag;
    chip.addEventListener("click", () => appendTag(tag));
    suggestionsEl.appendChild(chip);
  }
}

function appendTag(tag) {
  const parts = tagsInput.value.split(",");
  parts[parts.length - 1] = ` ${tag}`;
  tagsInput.value = `${parts.join(",").trim()}, `;
  tagsInput.focus();
  renderSuggestions();
}

// --- Form population --------------------------------------------------------

async function loadCurrentTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) {
    return;
  }

  urlInput.value = tab.url || "";
  openUrl.href = tab.url || "#";
  titleInput.value = tab.title || "";

  if (tab.favIconUrl) {
    faviconEl.src = tab.favIconUrl;
    faviconEl.hidden = false;
  }
}

async function loadTags() {
  const result = await send({ action: "apiCall", method: "GET", path: "/api/v1/tags" });
  if (result.ok && Array.isArray(result.data)) {
    knownTags = result.data.map((tag) => tag.name);
  }
}

// --- Actions ----------------------------------------------------------------

async function fetchMetadata() {
  hide(formError);
  fetchButton.disabled = true;
  fetchButton.textContent = "Fetching…";

  const result = await send({
    action: "apiCall",
    method: "POST",
    path: "/api/v1/metadata",
    body: { url: urlInput.value }
  });

  fetchButton.disabled = false;
  fetchButton.textContent = "Fetch metadata";

  if (!result.ok) {
    showError(formError, escapeHTML(result.error || "Could not fetch metadata."));
    return;
  }

  const data = result.data || {};
  if (!titleInput.value.trim() && data.title) {
    titleInput.value = data.title;
  }
  if (!descriptionInput.value.trim() && data.description) {
    descriptionInput.value = data.description;
  }
}

async function save() {
  hide(formError);
  saveButton.disabled = true;
  saveButton.textContent = "Saving…";

  const tags = parseTags(tagsInput.value);
  const result = await send({
    action: "apiCall",
    method: "POST",
    path: "/api/v1/bookmarks",
    body: {
      url: urlInput.value,
      title: titleInput.value.trim(),
      description: descriptionInput.value.trim(),
      tags,
      fetchMetadata: false
    }
  });

  saveButton.disabled = false;
  saveButton.textContent = "Save";

  if (result.ok) {
    showSaved(result.data, tags);
    return;
  }

  if (result.status === 409 && result.existingID) {
    const link = bookmarkURL(result.existingID);
    showError(
      formError,
      `Already saved. <a href="${link}" target="_blank" rel="noopener noreferrer">View bookmark ↗</a>`
    );
    return;
  }

  showError(formError, escapeHTML(result.error || "Could not save the bookmark."));
}

function bookmarkURL(id) {
  return `${(serverURL || "").replace(/\/+$/, "")}/app/bookmarks/${id}`;
}

function showSaved(bookmark, tags) {
  savedTitle.textContent = (bookmark && bookmark.title) || titleInput.value || urlInput.value;
  savedTags.textContent = tags.join(", ");

  const viewButton = document.getElementById("view-bookmark");
  viewButton.onclick = () => {
    clearTimeout(autoCloseTimer);
    chrome.tabs.create({ url: bookmarkURL(bookmark.id) });
    window.close();
  };

  showState("saved");
  autoCloseTimer = setTimeout(() => window.close(), 3000);
}

// --- Wiring -----------------------------------------------------------------

document.getElementById("open-settings").addEventListener("click", () => {
  chrome.runtime.openOptionsPage();
  window.close();
});

fetchButton.addEventListener("click", fetchMetadata);
saveButton.addEventListener("click", save);
tagsInput.addEventListener("input", renderSuggestions);

async function init() {
  const status = await send({ action: "getStatus" });
  serverURL = status.serverURL;

  if (!status.configured) {
    setupMessage.textContent = "Set up Stash to start saving bookmarks.";
    showState("setup");
    return;
  }

  if (!status.signedIn) {
    setupMessage.textContent = "Sign in to save bookmarks to your Stash instance.";
    showState("setup");
    return;
  }

  showState("form");
  await loadCurrentTab();
  await loadTags();
}

init();
