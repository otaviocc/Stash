# Contributing

Thanks for considering a contribution to Stash.

## Before you start

Read [`CLAUDE.md`](https://github.com/otaviocc/Stash/blob/main/CLAUDE.md) for the repo layout
and conventions, and [`DECISIONS.md`](https://github.com/otaviocc/Stash/blob/main/DECISIONS.md)
for the running log of what was built and why — most non-obvious rationale lives there rather
than in code comments. [`PRODUCT.md`](https://github.com/otaviocc/Stash/blob/main/PRODUCT.md)
is the product spec.

## Building and testing

Each component is its own package/project — see the matching guide under
[`Docs/`](https://github.com/otaviocc/Stash/tree/main/Docs) before you start:

- Backend — [`Docs/backend-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/backend-build.md)
- CLI / StashKit — [`Docs/cli-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/cli-build.md),
  [`Docs/stashkit.md`](https://github.com/otaviocc/Stash/blob/main/Docs/stashkit.md)
- iOS / macOS apps — [`Docs/mobile-build.md`](https://github.com/otaviocc/Stash/blob/main/Docs/mobile-build.md)
- Browser extension — [`Docs/browser-extension.md`](https://github.com/otaviocc/Stash/blob/main/Docs/browser-extension.md)

CI (`.github/workflows/ci.yml`) runs three jobs — `backend`, `apple`, `extension` — matching
those same components. Your change should pass whichever job(s) it touches.

## Code style

Backend and app code is formatted with `swiftformat` and linted with `swiftlint`; both must
report clean (`swiftformat . --lint`, `swiftlint lint`, run from within `Backend/` or
`StashApp/`). The browser extension has no build step — `make lint` in `Extension/` is the
CI gate there. See the "Code style" section of `CLAUDE.md` for the hand-applied conventions
(comment placement, SwiftUI view decomposition, commit message format) not fully covered by
the linters.

## Docs

If your change affects the API surface, update `Backend/Public/openapi.yaml` in the same
commit (see `CLAUDE.md`). If it changes user-facing behavior, update the relevant guide under
`Docs/`.

## Pull requests

Keep PRs focused on one change. Commit messages follow
[the seven rules](https://cbea.ms/git-commit/): imperative, capitalized, period-free subject
line ≤ 50 chars, with a body explaining *why*.
