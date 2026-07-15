# Stash Decisions: Cross-cutting Conventions, Code Style & Project Structure

_Part of the Stash Decision Log. See [`DECISIONS.md`](../DECISIONS.md) for the index and the full list of topical files. Entries are in original chronological order within this file._

---

## Cross-cutting conventions

I replaced Vapor's default error middleware with a custom `StashErrorMiddleware`
so every API error, including routing 404s and validation failures,
serializes to the same `{ error, code, message }` envelope (§17.4).
Strongly-typed `APIError` cases own the status/code/message mapping, and the
duplicate-URL case carries an extra `existingID`.

For testing I settled on `VaporTesting` + swift-testing running against an
in-memory SQLite database (§17.7) rather than Postgres, fast and isolated,
and production still runs on Postgres; the only schema concession is that
array/JSON columns map slightly differently per driver (more on that in M2).
I never got around to unit-testing the Leaf templates themselves (§17.7);
Leaf errors only show up at render time, and the existing suite can't catch
them, so each web feature gets a throwaway end-to-end smoke test (log in, do
the thing, assert) that I run once and delete.

One dependency snuck outside what §17.2 lists: `fluent-sqlite-driver`, needed
because §17.7 requires an in-memory SQLite test database. Postgres is still
the production driver.

---

## Linting & formatting (SwiftLint + SwiftFormat)

I found that SwiftFormat's organization rules (`organizeDeclarations` and
`markTypes`) are opt-in and disabled by default, and the config had supplied
all their options without ever actually turning the rules on, so no MARK
organization was happening at all. Enabling both applies an MIT header, a
`// MARK: - <Type>` before each type, and in-type sections ordered
Nested Types → Static Properties → Properties → Computed Properties →
Lifecycle → Functions, public before private within each section. I chose
type-mode organization over visibility-mode deliberately: the codebase is
overwhelmingly `internal`-access, so visibility mode would have mostly
produced `Internal`/`Private` headings rather than anything meaningful.
`Package.swift` stays untouched by the header rule, since SwiftFormat already
knows to keep `// swift-tools-version:` on line 1.

Three SwiftLint rules got disabled because they false-positive on Fluent's
query DSL: `first_where`, `contains_over_first_not_nil`, and `empty_string`
all want to rewrite database-builder calls as if they were plain `Sequence`
operations, which would break compilation. A handful of idiomatic short
names (`db`, `q`, `i`, `a`, `b`, `c`, `s`, `v`, `ok`, `ts`, `me`) are
excluded from `identifier_name` rather than renamed everywhere. I also
disabled the length-based rules (`file_length`, `type_body_length`,
`function_body_length`) for consistency with the complexity rules already
off in the config: the web controllers and test suites legitimately run
long, and this is easy to revisit with soft thresholds if I ever want a
gentle nudge instead of silence. End state: zero lint violations, idempotent
formatting, a clean build, 65 passing tests.

---

## Code style: comments and documentation

I don't allow comments of any kind inside method or function bodies: code
and tests are the documentation, and if a body needs a `//` explaining what
it does, that's usually a sign that the code itself isn't clear enough. All
documentation lives at the declaration level instead. (The one exception is
the backend tests' `// Given` / `// When` / `// Then` structure markers,
below.) I initially said doc comments were for types only, but that turned
out to be un-enforceable: SwiftFormat's `--doc-comments before-declarations`
auto-upgrades any `//` placed before a declaration into a `///` doc comment
regardless of what kind of declaration it is, so the rule now just reflects
what the formatter actually produces: doc comments are fine on types,
properties, and methods alike. Everything is American English throughout:
`behavior`, not `behaviour`; `color`, not `colour`, including test
descriptions, which follow Given/When/Then structure with every expectation
phrased as "It should …".

## Code style: blank lines

A blank line after the last `guard` in a group is enforced automatically by
SwiftFormat. Blank lines before `if`/`for`/`switch` and before a `return` in
a multi-statement body aren't: neither SwiftFormat nor SwiftLint has a rule
for it, and building a custom one felt fragile, so that one stays a
hand-applied convention rather than a machine-enforced rule.

## Code style: commit messages

I follow the seven rules of a good commit message
([cbea.ms/git-commit](https://cbea.ms/git-commit/)): separate subject from
body with a blank line, keep the subject under 50 characters, capitalize it,
no trailing period, imperative mood ("Add", "Fix", not "Added"/"Adds"), wrap
the body at 72 characters, and use the body to explain what and why, not
how. Nothing enforces this with a hook: it's just discipline. A single
cohesive change gets prose paragraphs; a commit grouping several distinct
changes gets `-` bullets. I went back and reworded the whole repository's
early history at one point so every subject line actually fit in 50
characters.

## iOS/macOS project: committed, off XcodeGen

I originally generated the Xcode project from `project.yml` with XcodeGen
and gitignored the `.xcodeproj` itself, but reversed that decision: the
project is committed now and XcodeGen is gone. Two things drove the switch:
regenerating kept wiping out Xcode's "update to recommended settings," and I
wanted the modern synchronized-folder format where a folder on disk is
referenced once instead of every file being individually listed in the
project. `xcuserdata/` stays gitignored; the shared schemes are committed.
Since membership in synchronized folder groups is folder-level, it fits this
codebase well: platform splits are already `#if`-guarded rather than
per-file, so `Common/` maps to all four targets, `Stash/` to both apps,
`StashShareExtension/` to both extensions. I did this conversion inside
Xcode itself rather than scripting a `.pbxproj` rewrite: round-tripping
through `plutil` emits an XML-format project that breaks `xcodebuild`'s
package resolution and scheme autocreation, so tooling shouldn't try to
regenerate this project. I also renamed the outer cross-target `Shared/`
folder to `Common/` and flattened the inner, app-only `Stash/Shared/` up
into `Stash/` directly, since once the outer folder was `Common/` the inner
`Shared/` name was just redundant.

## Merged the iOS and macOS targets into multiplatform targets

M10 had created genuinely separate iOS and macOS targets. With SwiftUI
there's no real reason for that split, so I collapsed all four targets down
to two multiplatform ones (`Stash` and `StashShareExtension`) supporting
iPhone, iPad, and Mac from one scheme selected by run destination. This
needed zero Swift changes, since the code was already `#if`-guarded and the
single `@main` already branched per platform. Per-platform `Info.plist` and
entitlement differences (a handful of keys, plus macOS-only sandbox and
network-client entitlements) moved into a small non-synced `Config/` folder,
selected by SDK-conditional build settings, which also happened to fix a
stray-`Info.plist` defect the synchronized-folders conversion had
introduced, since with no plists inside the synced folders there's nothing
that can leak into the wrong bundle. I edited the project file with the
`xcodeproj` Ruby gem rather than `plutil`, for the same XML-round-trip
reason as before, and verified the result by building both destinations
cleanly from the one scheme.

## StashApp: fixed miscategorized files within `Stash/`

I kept the macro `Common/` / `Stash/` / `StashShareExtension/` split as-is,
since it encodes real Xcode target membership rather than just taste: files
in `Stash/` look shareable at a glance, but `Stash/` *is* the iOS↔macOS
shared layer already; its stateful repositories, the SwiftData store, and
the sync engine are app-only by design, and pulling them into `Common/`
would bloat the process-isolated, online-only Share Extension with code it
can't use. I did move three files to the subfolder that actually matched
what they are: `LocalStore` and `LocalBookmark` into a new `Persistence/`
subfolder (a service and a persistence entity, not "Models" in the domain
sense), `BookmarkFilter` into `Support/` (a stateless helper enum, not a
repository), and `SyncModifiers` into `Views/` (a SwiftUI `ViewModifier`,
same kind as another modifier already living there). All pure disk moves:
synchronized folder groups pick them up automatically with no project file
edit.

## Documentation

All documentation ended up consolidated into one top-level `Docs/` folder:
I merged every component's docs in and deleted the per-component READMEs
that had accumulated, leaving the root `README.md` as a concise landing page
that links into `Docs/`. The standing rule going forward: a new component or
feature gets one guide in `Docs/`, never a `Component/README.md`: the
browser extension actually shipped with its own README first and I folded
it into `Docs/browser-extension.md` shortly after, to match everything else.
The `caddy/` directory of committed Caddyfile variants also got folded into
`Docs/backend-docker-caddy.md` and removed: now there's a single documented
source of truth as copy-paste blocks, instead of files in the repo that
could quietly drift from the walkthrough describing them.

---

## Markdown style: hard line breaks

All Markdown in this repo uses hard line breaks, prose wrapped at 80
characters, rather than long flowing paragraphs: it's easier to read in a
plain text editor and produces cleaner, more reviewable diffs. Code blocks,
tables, and headings are left alone, since tables in particular can't be
narrowed without losing their structure.

---

## SwiftUI view decomposition convention (native apps)

I settled on a consistent way to break up SwiftUI views across the whole
app: a sub-piece of a view is a private `make…() -> some View` function,
named `make` plus whatever it produces, rather than a computed-`var`
subview: a style I'd already used throughout a sibling project and liked
enough to standardize here. `var body` stays a small composition of those
`make…()` calls instead of one sprawling view tree; a plain, non-view
computed property like `isValid` or a navigation title stays a normal `var`,
since only `some View`-returning members get the function treatment. I
applied this across the whole app in one pass: converting existing
computed-var subviews, renaming a handful of view-returning functions that
didn't follow the `make` prefix, and slicing several of the larger bodies
(the bookmark detail screen, login, the Smart View form, the sidebars) into
proper pieces. Purely structural, with identical view trees and modifier
order: no behavior changed. SwiftFormat's organization rule files these
under one consistent MARK automatically, so I never have to hand-place them.

---

## Per-machine signing & bundle identifier (xcconfig)

I build this app under two different Apple developer accounts on two
different machines, each with its own bundle prefix. Previously the team id
and prefix were hardcoded throughout the committed Xcode project, several
entitlement files, several Info.plists, and a handful of Swift constants:
switching machines meant editing tracked files by hand and risking
accidentally committing the wrong account's identifiers.

Now there's exactly one source of truth: a committed base xcconfig file
defining the bundle prefix and the development team, wired in at the
project level so both targets inherit it. A second, gitignored xcconfig can
optionally override either value on a given machine: present, it wins;
absent, the committed defaults apply silently, so the primary machine needs
no extra file at all. Every bundle-keyed identifier (the app's bundle id,
the extension's, the App Group name, the exported file type, the background
task identifier) derives from that one prefix at build time and again at
runtime by reading it back out of the built app's own Info.plist, so the
build settings and the Swift constants can never drift apart from each
other. Change the one xcconfig line, and the whole graph of derived
identifiers follows automatically.
