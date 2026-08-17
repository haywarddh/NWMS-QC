# NWMS Quality Records — version history

## Versioning scheme

Semantic Versioning (MAJOR.MINOR.PATCH), shown in the app as **"Beta v0.6.2"** —
"Beta" is the human-readable flag, and MAJOR staying at 0 is the same signal in
SemVer terms. Deliberately identical in spirit to the Weekly Delivery Planner's
scheme, so the two apps are versioned the same way.

- **MAJOR** (currently 0) — stays 0 through beta. Moving to 1.0.0 marks the point
  the team agrees this is out of beta: a deliberate, discussed decision, not
  something that happens as a side effect of feature work.
- **MINOR** — a new feature or a meaningful capability change; the kind of thing
  you would mention in a UAT email. Reset PATCH to 0.
- **PATCH** — fixes, small tweaks, copy changes, minor polish.

### Where the version lives — and why it is checked

**One version covers the whole deployment.** Quality Records ships as two
artefacts that are always published together:

| File | What carries it |
|---|---|
| `qc\src\lib\version.ts` | `APP_VERSION` — compiled into the front-end bundle |
| `qc-api\qc-api.ps1` | `$ServiceVersion` — reported by `/api/health` and the startup banner |

A tester only ever reports one number. If the front end said 0.5.0 while the
service said 0.4.1, that number would identify nothing. So **the publisher reads
both and refuses to publish when they disagree** — the protocol is enforced, not
merely written down.

Where it is shown:

- **Every page footer**, alongside which service answered (LIVE / DEV / LOCAL) —
  during UAT most reports arrive as "it did something odd", and a build number
  plus an instance name is what makes that actionable.
- **`GET /api/health`** — `version` and `instance`.
- **The customer report footer**, because a customer's copy outlives the
  conversation about it and "which version printed this?" is otherwise
  unanswerable a year later.

### Releasing

1. Bump `APP_VERSION` **and** `$ServiceVersion` to the same number.
2. Add an entry below.
3. `npm run build` — the version is compiled into the bundle, so a publish
   without a rebuild ships the old number.
4. Publish to **Dev** (`\\NW-APPSERVER\NWMS_QC_Dev`, port 8792) for extended UAT.
5. Live (`\\NW-APPSERVER\NWMS_QC`, port 8791) **only when Dave expressly asks**.

`qc-api\CHANGELOG.md` keeps its own detailed service-level history; this file is
the project-level record.

---

## History

### 0.6.2 — 2026-08-18

**Fixed: the drawing zoom controls (−/%/+/fit) had no effect.** They sit
inside the same canvas that captures the pointer on press to track a
possible drag-pan, and nothing stopped that capture from happening when
the press landed on a button first — so the canvas grabbed the interaction
before the button's own click could ever fire. The zoom percentage shown
in a bug report was real; it came from the mouse wheel or a pinch gesture,
a separate code path with no such problem, which is what made the buttons
look broken while zooming itself clearly worked. The PMP balloons on the
drawing solve the identical problem already, one layer down — the fix
gives the three zoom buttons the same guard. Verified against a real
loaded drawing with the actual pointer-event sequence a click produces,
not just a synthetic click: zoom in, zoom out and fit all move the
percentage and the drawing's visible scale exactly as expected.

### 0.6.1 — 2026-08-17

**Fixed mojibake on the Capability page** and in `fonts.css`'s comments —
em dashes, an ellipsis, an en dash, a middle dot, σ and ✳ had all been
saved as UTF-8 text that was first misread as Windows-1252 and re-saved,
turning one correct character into two or three wrong ones (an em dash
became `â€"`, for instance). Confirmed present in the repository before
this session's own work began, so not something introduced by anything
built today. A repo-wide search found only these two files genuinely
affected — every other file that matched an initial broad search turned
out to contain correctly-encoded characters (±, °, ·) that only
*resembled* the corruption pattern; each was individually verified,
line by line, before either file was touched, specifically to avoid
"fixing" text that was already right.

### 0.6.0 — 2026-08-17

**PMPs can now be satisfied by an InspecVision 3D-scan check** — one
control-plan characteristic verified by scanning many dimensions at once
(the flat pattern's accuracy, and dimensions unaffected by later forming),
rather than one manually-measured value.

- A "good / no good" PMP verified by InspecVision gets a new panel: drop an
  export in, and it's parsed (InspecVision's own format — UTF-16 with a byte-
  order mark, tab-delimited, not the comma-separated shape the existing CSV
  importer expects), merged against whatever was uploaded before, and
  deduplicated on feature name + inspection timestamp — because InspecVision's
  own export is itself cumulative, appending to the same file until someone
  archives it on their end, so re-uploading it will substantially overlap a
  prior upload.
- Shows a live summary — features, runs, rows currently failing — plus which
  features are trending the same direction run after run (usually means a
  laser program or a tool moved, not noise), and the full detail one scroll
  away.
- The scan data itself lives outside the autosaved plan body, in a new
  service-side store (`qc-api` 0.6.0, `/api/scans`) — the same reason photos
  do: this can run to thousands of rows over a plan's life, and the whole
  plan is re-PUT on every 700ms autosave.
- Readiness, Capability and the customer report all recognise this evidence
  with **no changes to any of the three** — a scan derives one ordinary
  reading per run ("good"/"no good"), so the same "any failure blocks
  readiness" rule that already governs every other PMP applies here too.
- Fixes a related gap found while building this: amending a plan without
  carrying evidence forward left a PMP's prior scan summary visible even
  though the readings it was drawn from had just been cleared — the panel and
  the readiness machinery would have disagreed about the same PMP.

### 0.5.5 — 2026-08-17

**Header rebuilt as two rows: logo/status, then nav.** Two separate problems,
fixed together because both lived in the same container:

- The nav used to horizontal-scroll once it ran out of room, with the
  scrollbar hidden. Below about 1650px wide -- which includes 1366×768, one of
  the most common laptop resolutions there is -- **Approval, Customer report,
  Records and Library were completely hidden**, with no visible hint that
  more nav existed. It now wraps onto a second line instead, so every item is
  always visible regardless of screen width.
- The header used to change WIDTH depending which page you were on -- edge to
  edge on Dashboard, Drawing & plan, Evidence, Capability and Review, but
  centred and 1600px-capped everywhere else -- because it read the same
  `wide` flag meant for page content. The header no longer reads it at all;
  it is now the same width on every page. Page content is unaffected: `wide`
  still works exactly as before for that.

### 0.5.4 — 2026-08-17

**Knowledge base layout cleaned up.** Both tabs (failure lines, station rows)
were a 2-column card grid — expanding one row to edit it left a tall card
jammed next to a short neighbour, jagged and uneven. Both are now a single
column, so opening a row just pushes everything below it down cleanly.
Station rows also gained a search box (station code, wording), matching what
failure lines already had — previously the only way to find one among 17+
was to scroll and read.

### 0.5.3 — 2026-08-17

**"Start the ISIR" fixed** — and with it every other "create new" action in the
app: new PMPs, route steps, FMEA rows and actions, gauge R&R studies, template
saves, revisions, CSV uploads, manual checks. All of them mint a new id via
`crypto.randomUUID()`, which browsers restrict to secure contexts (HTTPS, or
`localhost`). This app is deliberately plain HTTP on the LAN, so on the
deployed URL `crypto.randomUUID` does not exist at all — every one of those
actions threw immediately, silently, with nothing shown in the app and nothing
but a console error to say why. It never showed up in testing because Vite's
dev server runs on `localhost`, which is exempt.

Fixed with one shared helper (`newId()` in `src/lib/utils.ts`) that falls back
to building a v4 UUID from `crypto.getRandomValues()` — which carries no such
restriction — when `randomUUID` is unavailable, and replaces all 22 call sites
across the app. Confirmed the fallback produces correctly-formed, unique ids
before shipping it.

### 0.5.2 — 2026-08-17

**PDF drawing upload fixed** — broken since it was built, everywhere except the
Vite dev server. The static file server had no `.mjs` case in its content-type
map, so pdf.js's module-worker renderer was served as `application/octet-stream`
and every browser refused to run it. See `qc-api\CHANGELOG.md` for the detail;
confirmed with a real end-to-end upload, not just a header check.

### 0.5.1 — 2026-08-17

The service window now says which instance it is on **every** line, not just once
at startup.

- **The instance label rides the request log.** `qc-api` writes a line per HTTP
  request to its own console, so the startup banner — the only thing distinguishing
  a LIVE window from a DEV one — scrolled out of view within seconds of real use.
  Every request line now leads with `[LIVE]` / `[DEV]` / `[LOCAL]`, and a fuller
  identity line (`---- [LIVE] qc-api v0.5.1 -- http://+:8791/ -- PID 1234 ----`)
  is re-printed every 25 requests, which is under a default 30-row window so at
  least one is always on screen.
- Considered and rejected: setting the console **window title** from the service.
  It sounds like the obvious answer, but under Windows Terminal the window title
  follows the *active tab*, so a background LIVE tab is not what the taskbar
  shows — and the launchers already set a title anyway. Also rejected: a sticky
  header (measured — it corrupts the line it overwrites and does nothing under
  Windows Terminal) and colour-coding (`DarkMagenta` *is* the background on the
  classic blue PowerShell window).
- An unlabelled ad-hoc run is unchanged: no label means no tag, byte-for-byte as
  before.

**Correction to the 0.5.0 note below:** 0.5.0 did **not** reach both shares. Live
(`\\NW-APPSERVER\NWMS_QC`) holds 0.4.1 with a pre-versioning bundle that carries
no version string at all; only Dev (`NWMS_QC_Dev`) received 0.5.0. Live is
therefore still awaiting its first versioned publish, which per the protocol
happens only when Dave expressly asks.

### 0.5.0 — 2026-08-17

First numbered release, and the first deployment to NW-APPSERVER.

- **Versioning protocol introduced** (the section above): a single version across
  both artefacts, shown in the page footer, the health endpoint and the customer
  report, with the publisher enforcing that the two files agree. Before this the
  app displayed no version at all — a build in the wild could not be identified.
- **Published to `\\NW-APPSERVER\NWMS_QC_Dev`** (Dev, 8792), 76 files / 3.01 MB.
  Live (`NWMS_QC`, 8791) was published earlier the same morning, *before* this
  version bump, so it carries 0.4.1 — see the correction under 0.5.1 above.
- **`Start Quality Records Dev Server.cmd`** added, and both launchers now refuse
  to run from the wrong share — the Live launcher in a `_Dev` folder would have
  served Dev data on Live's port, and the Dev launcher in the Live folder would
  have exposed controlled records on the Dev port.
- Footer states plainly that there is **no authentication and this is LAN-only
  use**, because that is the whole access-control model and it should not be
  something you have to remember.

The state of the app at this release, built over 2026-08-16/17:

- **APQP spine** — process route → step-level AIAG-VDA FMEA with Action Priority →
  control plan ballooned on the drawing → per-instance evidence → review →
  three-role NWMS sign-off → customer approval.
- **Issued plans are frozen**; changing one means an explicit amendment that
  creates a new revision and leaves the original standing.
- **Shared company libraries** — route templates, failure lines and 17 station
  FMEA rows transcribed from the real 1394250-3-105 workbook — with their own
  Library page, usable with no plan open.
- **Photographic evidence** at three levels (characteristic, individual reading,
  submission), stored outside the plan body and downscaled before upload.
- **Printable customer-facing ISIR report** that declares its own gaps on its
  face rather than hiding them.
- **Password-gated privileged actions** and an audited un-archive.
- Deployment tooling: configure, publish, rollback and verified data backup, all
  refusing to touch `data\`.
