# NWMS Quality Records — version history

## Versioning scheme

Semantic Versioning (MAJOR.MINOR.PATCH), shown in the app as **"Beta v0.5.0"** —
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

### 0.5.0 — 2026-08-17

First numbered release, and the first deployment to NW-APPSERVER.

- **Versioning protocol introduced** (the section above): a single version across
  both artefacts, shown in the page footer, the health endpoint and the customer
  report, with the publisher enforcing that the two files agree. Before this the
  app displayed no version at all — a build in the wild could not be identified.
- **Published to both shares**: `\\NW-APPSERVER\NWMS_QC` (Live, 8791) and
  `\\NW-APPSERVER\NWMS_QC_Dev` (Dev, 8792), 76 files / 3.01 MB each.
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
