# Changelog — qc-api

## 0.6.1 — 2026-08-17

Version bump only -- nothing in this file changed. See the root `CHANGELOG.md`;
the fix is a source-encoding correction in two front-end files.

## 0.6.0 — 2026-08-17

Adds `/api/scans`, a second blob store alongside `/api/attachments` — one
merged, deduplicated InspecVision dataset per file, referenced by a small id
a PMP carries instead of holding the rows itself. One content type
(`application/json`) instead of three image types, so no magic-byte sniff
and no multi-extension resolve; POST does a cheap "starts with `[`" sanity
check rather than a full `ConvertFrom-Json`, for the same PS 5.1 large/deep-
JSON reason plan bodies are stored as raw strings. 25 MB cap per blob (higher
than attachments' 15 MB — there is no client-side downscale step for this
data, and it only grows over a plan's life). New `$ScansDir`, `Test-ScanId`/
`New-ScanId`/`Resolve-ScanPath`, `Invoke-ScanPost`/`Get`/`Delete`, and a new
SCAN DATA section in the header comment alongside ATTACHMENTS. See the root
`CHANGELOG.md` for the feature this exists to support.

## 0.5.5 — 2026-08-17

Version bump only -- nothing in this file changed. See the root `CHANGELOG.md`;
the fix is entirely in the front end's header.

## 0.5.4 — 2026-08-17

Version bump only -- nothing in this file changed. See the root `CHANGELOG.md`;
the fix is entirely in the front end's Knowledge base panel.

## 0.5.3 — 2026-08-17

Version bump only -- nothing in this file changed. The fix behind this release
is entirely in the front end (a `crypto.randomUUID()` call that throws outside
a secure context); see the root `CHANGELOG.md`. Noted here anyway rather than
left as a silent gap: this service answered `/api/health` with "0.5.3" at some
point, and a changelog that skips a version a client actually reported is
exactly the kind of gap this file exists to avoid.

## 0.5.2 — 2026-08-17

Fixes PDF drawing upload, which was broken everywhere except the Vite dev
server.

- **`.mjs` added to the static content-type map.** pdf.js loads its rendering
  engine as an ES module worker (`new Worker(url, { type: "module" })`), and
  browsers strictly refuse a module script unless it is served with a
  JavaScript MIME type. `.mjs` was missing from `Get-StaticContentType`, so it
  fell to the `default` case -- `application/octet-stream` -- and every upload
  of a customer drawing PDF failed with a bare, generic "could not be read"
  message in the app, while the browser console held the real reason:
  `Failed to load module script: ... non-JavaScript MIME type`.
- This is not a regression from anything published this week: the local qc-api
  instance on port 8791 had the identical bug, confirmed directly. It surfaced
  now because testing had only ever gone through the Vite dev server, which
  has correct module MIME handling built in and was never exposed to it.
- Verified end to end, not just by inspecting the response header: a real File
  object was driven through the actual `/new` upload control and rendered to a
  preview canvas with zero console errors, against a throwaway instance running
  the exact same build about to be published.

## 0.5.1 — 2026-08-17

The console now identifies itself on every line it prints.

- **`-InstanceLabel` is stamped on every request-log line**, leading it:
  `[LIVE] 2026-08-17 09:14:02  GET     /api/plans  ->  200  (7 ms)`. The label was
  previously only in the startup banner, which this service scrolls out of view
  itself: it logs a line per HTTP request to the same console, so within seconds
  of real use a LIVE window and a DEV window are again two identical walls of log.
  A left-aligned tag can be read straight down the edge of the window without
  reading the lines.
- **A fuller identity line every 25 requests**:
  `---- [LIVE] qc-api v0.5.1 -- http://+:8791/ -- PID 1234 ----`. The per-line tag
  has no room for version, address and PID. 25 is under a default 30-row window,
  so at least one of these is on screen at any moment rather than merely usually.
- The 500-handler's `ERROR` line carries the tag too, so the lines that matter
  most are not the ones missing their instance.
- **No label means no tag.** A bare `qc-api.ps1` run for ad-hoc work prints
  exactly what it printed before.
- Not done, deliberately: the console **window title**. Under Windows Terminal the
  window title follows the active tab, so a background LIVE tab is not what the
  taskbar or Alt-Tab shows; the launchers set a title already; and a title set
  from inside a script is console-scoped, outliving the process that set it.
  A sticky header was measured and rejected — it corrupts the line it overwrites,
  does nothing where the buffer equals the window, and throws once output is
  redirected.

> **Version gap:** this file jumps 0.4.0 → 0.5.1. Versions 0.4.1 and 0.5.0 were
> tagged during the deployment work without service-level notes; 0.4.1 is what
> sits on the Live share today. The gap is left visible rather than back-filled
> from memory.

## 0.4.0 — 2026-08-17

Everything here exists to make a real NW-APPSERVER deployment possible and safe.
Nothing about the API's behaviour changed for the front-end.

- **`-ListenAddress` (default `localhost`).** The prefix is now
  `http://<ListenAddress>:<port>/`. `+` binds every interface, which is what the
  server needs. The default stays `localhost` deliberately: a bare invocation
  should never put an app with no user accounts onto the network by accident.
- **A plain-English answer to `Access is denied`.** Binding anything other than
  `localhost` is privileged, and the raw .NET failure says only "Access is
  denied" — which reads like a folder or share permission fault and sends people
  hunting in the wrong place. It is http.sys refusing the binding. That one case
  is now caught and explained, naming both fixes (run elevated, or reserve the
  URL once) and printing the exact `netsh http add urlacl` line for the address
  and port actually in use. This is the single most likely first-deployment
  stumble, so it explains itself in the window where it happens.
- **`-InstanceLabel`** — printed in the startup banner (with the Planner's
  LIVE-in-red / other-in-magenta convention) and returned by `/api/health` as
  `"instance"`. Two identical black console windows is how someone stops, or
  publishes over, the wrong one; and a monitoring check can now confirm it is
  talking to LIVE before it believes a version number.
- **Service lock: one service per data folder, enforced.** An exclusive lock is
  taken on `<DataDir>\qc-api.lock` **before** the listener starts and held for
  the process lifetime, mirroring the Planner's `planner-service.lock`. Two
  services sharing one data folder would interleave writes to `plans\index.json`
  and lose records from the list while they still sat on disk. A second instance
  on the same folder prints what is wrong, how to find the holder by command line
  (`netstat` is useless here — http.sys reports the socket as PID 4, "System"),
  and exits **without** starting the listener. A Dev instance alongside Live is
  still fine: it just needs its own `-DataDir` and `-Port`.
  - The lock is a genuine OS file lock, not a flag file, so it cannot produce a
    false positive: if the process is killed the OS releases it, and a leftover
    `qc-api.lock` file is reclaimed on the next start.
  - The file is stamped with the PID, machine, instance label, start time,
    prefix and data folder. `FileShare::None` means nobody can read it while it
    is held — which is the right way round, because the question "which process
    was that, and since when?" only gets asked about a leftover file after a
    crash or a `taskkill`.
- The lock is released and the file removed in the `finally` block, so `Ctrl+C`
  and a failed listener start both clean up after themselves.
- The banner now also states, on every LAN-bound start, that the app has no
  authentication and the firewall rule must stay Domain-profile and LAN-only.

## 0.3.1 — 2026-08-17

- **Content is checked against the declared type.** `POST /api/attachments` now
  reads the leading magic bytes (`FF D8 FF` for JPEG, the 8-byte PNG signature,
  `RIFF….WEBP`) and returns 415 when they disagree with the `Content-Type`
  header. The header is a claim by the client; this is an evidence store, so
  the claim is verified. A mislabelled upload would otherwise sit in an ISIR
  until someone opened the report months later and found a broken image.
- **`X-Content-Type-Options: nosniff`** on attachment reads, so a browser
  cannot second-guess the stored type from the content.
- **Error replies no longer leak server paths.** The catch-all used to paste
  the raw .NET exception message — full filesystem paths included — into the
  JSON body. The detail now goes to the service console; the client gets
  `internal error - see the qc-api console for detail`.
- **A vanished data folder is re-created** rather than 500-ing, and a client
  that disconnects mid-upload is logged as `499` instead of a `500` that reads
  like a genuine crash.

## 0.3.0 — 2026-08-16

- **Added: attachment (photo) storage.** ISIRs need photographic evidence —
  elcometer readings, packing, labelling, reference shots of a defect — so
  images now get their own store, separate from the plan body.
  - `POST /api/attachments` → body is the **raw image bytes**, the type comes
    from the `Content-Type` header. Answers
    `201 {"id":"<32 hex>","contentType":"image/jpeg","bytes":N}`.
  - `GET /api/attachments/{id}` → the image bytes with the stored
    `Content-Type`, or `404 {"error":"not found"}`.
  - `DELETE /api/attachments/{id}` → `{"ok":true}`, idempotent.
- **Why photos are *not* embedded in the plan record.** A data URL on the plan
  looks simpler and is the wrong answer twice over: the whole plan body is
  re-uploaded on every 700 ms autosave, and the front-end also mirrors it into
  browser localStorage (a 5–10 MB cap). Either one breaks after a couple of
  phone photos. An image is now uploaded **once**, and the plan carries only
  the returned id.
- **Accepted types are `image/jpeg`, `image/png` and `image/webp` only**
  (anything else is `415`), with a **15 MB cap per attachment** (`413` over
  it). This is an evidence store for the QC app, not general file hosting.
- **Ids are server-generated** — 32 hex characters from
  `RandomNumberGenerator`. A client-supplied id is never trusted, and on
  read/delete the id must match `^[a-f0-9]{32}$` exactly (`400` otherwise),
  which is the path-traversal guard for `data\attachments\<id>.<ext>`.
- **The file extension is the type record**, so there is no sidecar metadata
  file to fall out of step: a `GET` resolves the file by trying `jpg`/`png`/
  `webp` and maps whichever exists back to a `Content-Type`.
- Reads send `Cache-Control: public, max-age=31536000, immutable` — ids are
  unique and content never changes under an id, so an edited photo is a new
  upload with a new id, never a new body under the old one.
- **Attachments are deliberately not cascade-deleted with a plan.** An amended
  revision can reference the same photo ids as the plan it was copied from, so
  cascading would destroy evidence still in use elsewhere. Orphaned files are
  cheap; destroyed evidence is not.
- Internals: request bodies for attachments are read as **raw bytes**
  (`MemoryStream`, honouring `Content-Length` where present, cap enforced
  *while* reading) rather than through the UTF-8 `StreamReader` used for JSON,
  which would silently replace every non-UTF-8 byte of a JPEG. Writes go
  through a new binary twin of `Write-FileAtomic` (`.tmp` + move, but
  `WriteAllBytes`), and `Send-Bytes` gained an optional `-CacheControl`.
- `data\attachments\` is created at startup alongside the other data folders.

## 0.2.0 — 2026-08-16

- **Added: password-gated privileged actions.** The app still has no user
  accounts (deliberately out of scope); instead a handful of destructive /
  sign-off actions are gated by **one shared password, checked server-side** so
  the secret never ships inside the front-end bundle.
  - `GET /api/privileged` → `{"configured":true|false}` — answers only *"is a
    password set at all?"*. It never returns the password or its hash.
  - `POST /api/privileged/verify` → body `{"password":"..."}`, answers
    `200 {"ok":true}` or `200 {"ok":false}`. A wrong password is deliberately
    **not** a `401`: it is an expected answer, not a transport error, and the
    front-end treats non-2xx as "the API is broken". `4xx` here is reserved for
    a genuinely malformed request (not JSON, or no `password` field).
- **Added: `data\settings.json`** —
  `{"privilegedPasswordHash":"<hex sha256>","updatedAt":"<iso>"}`. Only the
  SHA-256 hash is stored, never the plaintext. Written through the same
  atomic-ish `.tmp` + move, UTF-8 no BOM path as every other file.
- **First run seeds the default password `nwms-quality`** and prints a loud
  one-line console warning under the startup banner telling the operator to
  change it. To change it, generate a new hash and drop it into
  `settings.json`, then restart (recipe in the README). An *unparseable*
  `settings.json` is never silently overwritten — a hand-edit typo leaves
  privileged actions locked rather than resetting the password to the default.
- The front-end never stores the password: it posts it once per unlock and
  keeps only a boolean in React state, so a page reload re-locks everything.

## 0.1.1 — 2026-08-16

- **Fixed: index corruption when a second plan was saved.** `Read-PlanIndex`
  trusted `@(...)` to unroll `ConvertFrom-Json`'s result, but PowerShell 5.1
  returns a PSObject-*wrapped* array that `@(...)` does not unroll — so the
  whole existing index rode along as a single element and re-serialized as a
  corrupt `{"value":[...],"Count":n}` blob once a PUT for a *different* plan id
  arrived. Entries are now copied out with `foreach`, which enumerates the
  wrapper correctly. (Found minutes after first deployment, during end-to-end
  testing of the second saved plan.)

## 0.1.0 — 2026-08-16

Initial release.

- `System.Net.HttpListener` service on `http://localhost:8791/` (configurable
  via `-Port`), single-threaded request loop, PowerShell 5.1 compatible.
- Plan storage API: `GET /api/plans`, `GET /api/plans/all`,
  `GET/PUT/DELETE /api/plans/{id}` — plan bodies stored byte-for-byte as raw
  request strings (no PS JSON round-trip), `index.json` (PlanMeta[]) maintained
  newest-first from `record.meta` on every PUT.
- FMEA library storage: `GET/PUT /api/library` (raw body storage).
- `GET /api/health` liveness endpoint with version and plan count.
- Static hosting of the built front-end from `..\qc\dist` (configurable via
  `-WebRoot`) with SPA `index.html` fallback and a helpful 404 when the
  front-end has not been built yet.
- Atomic-ish writes (`.tmp` + move), UTF-8 without BOM throughout, plan-id
  sanitisation against path traversal, per-request console logging, per-request
  error isolation (any handler exception → 500, loop continues).
