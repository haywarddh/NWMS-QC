# NWMS Quality Records — version history

## Versioning scheme

Semantic Versioning (MAJOR.MINOR.PATCH), shown in the app as **"Beta v0.19.0"** —
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

### 0.19.0 — 2026-08-19

**The "New ISIR" wizard now leads with the drawing too.** It previously
required part number and customer before it would even let you load the
drawing — the more literal version of the same "retype what the drawing
already says" problem 0.18.0 fixed on the Drawing & plan page.

- **Step 1 is now "Customer drawing," step 2 is "Part details."** Loading
  the drawing first and reading its title block (same native-CAD-PDF
  parsing as 0.18.0) means step 2 often opens already filled in — check it,
  adjust anything, and continue.
- **"Skip for now" still works exactly as before**, now on step 1: type the
  part details by hand with no drawing yet if that is genuinely how you want
  to start, and add the drawing later from the Drawing & plan page.
- Nothing about step 3 (confirm & open) changed — same summary, same
  "starts the ISIR" action.

### 0.18.0 — 2026-08-19

**Importing the drawing is now the actual first step on the Drawing & plan
page, and a native CAD PDF export fills in its own part details.** Part
number, customer, drawing number and issue used to sit above the drawing
before anything was loaded — retyping what the drawing's own title block
already says, on a page whose first real action is importing that drawing.

- **The four part-detail fields are now hidden until there is something to
  show** — a loaded drawing, or part details already collected by the
  "New ISIR" wizard, which still asks for them earlier. On a genuinely
  fresh plan, the panel's first and only content is the import prompt.
- **A native CAD PDF export (SolidWorks/AutoCAD/Inventor "print to PDF" —
  anything that keeps its text real and selectable) has its title block
  read automatically**, filling in whichever of the four fields are still
  blank. A scanned or photographed drawing has no text layer to read at
  all, and simply leaves the fields exactly as blank and hand-fillable as
  they always were — there is no OCR here, deliberately, and nothing about
  this ever overwrites a value already typed.
- **A parsed value is always a starting point, never asserted as
  correct** — an amber note ("check these before continuing") appears
  whenever anything was read automatically, and every field stays a plain
  editable box exactly as before. Verified against a hand-built test PDF
  with a dense, multi-field title-block row and unrelated decoy text
  elsewhere on the sheet: every field landed on the right value and the
  decoys were correctly ignored.

### 0.17.0 — 2026-08-19

**Popping out the drawing now reclaims its space for the control plan, and
either window can bring it back.** On a drawing with many PMPs still to
place, the inline drawing panel sat there at full height even after the
whole point of popping it out was to work from the PMP list instead.

- **Popping out now collapses the inline drawing to a compact strip**,
  letting the control-plan table below it move up into the space the
  620px-tall canvas was using — the page bar (for switching sheets) stays,
  since that is still useful while popped out, but the canvas itself now
  renders in exactly one window at a time rather than sitting idle in both.
- **A "Re-dock" button in the popped-out window** closes it and restores
  the inline drawing, and **a "Bring it back" button in the same spot on
  the plan page** does the same from the other side — whichever window is
  in front when you are done.
- Closing the popout by its own window controls, without using either
  button, is caught too: the plan page notices within a second and
  restores the inline drawing on its own rather than being left thinking
  it is still popped out.
- Clicking "Pop out drawing" again while it is already open still just
  brings the existing window to the front, now labelled "Focus popped-out
  window" so it reads as a different action from opening it fresh.

### 0.16.0 — 2026-08-19

**The drawing can now be popped out into its own window**, for an engineer
annotating on a two-monitor setup — drag it to a second monitor and fill the
screen there, while the characteristics list and edit panel stay put on the
first.

- **"Pop out drawing"**, next to the drawing on the Drawing & plan page,
  opens the drawing alone in a new window — just the drawing, its zoom
  controls, and a Fullscreen button, with nothing else from the app
  competing for space on the second monitor.
- **The two windows stay in live sync, in both directions.** Selecting a
  PMP, drawing a new box, or dragging a box or label in either window
  updates the other immediately. There is still only one real copy of the
  plan: the popout carries no state and no autosave of its own, and every
  change it makes is carried out by the main window's existing mutators —
  the same way a remote control asks a TV to change channel rather than
  tuning itself. Verified directly: a box dragged in the popout landed at
  the exact same coordinates the main window would have produced itself.
- Clicking "Pop out drawing" again while the window is still open brings it
  to the front instead of opening a second one.
- If a browser's popup blocker steps in, the button now says so in plain
  terms rather than silently doing nothing.

### 0.15.1 — 2026-08-19

**Polished the box-and-leader style: rounded corners, an arrowhead, and a
proper edge-to-edge connection.** The box and label were sharp-cornered
rectangles, the label had no visible outline of its own, and the leader
line ran centre-to-centre — relying on the box's own fill to visually hide
the segment that crossed into it, rather than actually stopping there.

- **The highlight box and the label chip both now have rounded corners.**
  The box's radius is a percentage of its own size, so it scales with the
  drawing exactly the way the box itself does, rather than looking
  proportionally different at every zoom level.
- **The label now has a permanent visible chip** — a light background and a
  coloured border matching the box — instead of only showing an outline
  once selected.
- **The leader line now runs from the label's actual edge to the box's
  actual edge**, computed geometrically rather than assumed, with an
  arrowhead at the box end pointing at the feature — verified by hand
  against the exact stored coordinates, not just by eye.

### 0.15.0 — 2026-08-19

**The leader label is now plain text, sized like a real CAD annotation.**
The circular numbered badge and its value/tolerance chip, carried straight
over from the old point marker, no longer fit the new box-and-leader style
— and repeated a nominal/tolerance that is already on the drawing itself.

- **The label is now just the PMP reference as plain text** (e.g. "PMP01"),
  drawn at the end of the leader line — no circle, no dimension chip.
- **The label's text height is a fraction of the drawing's own width**,
  the same normalised convention the box already uses, rather than a fixed
  screen size — so, like a real CAD leader, it scales together with the
  drawing and with zoom instead of staying constant. Verified directly: a
  130% zoom grew the label by exactly 130%, matching the box precisely.
  The text size itself is tuned by eye for a typical A4–A2 engineering
  sheet, not measured from the file — nothing about an uploaded image or
  PDF reliably says what real sheet size it was printed at, so if it reads
  too large or small on your actual drawings, it's a one-line constant to
  retune.
- Still independently draggable and still selects the PMP on a plain
  click, exactly as before — only how the label is drawn changed, not how
  it behaves.

### 0.14.0 — 2026-08-19

**Replaced the simple circular marker with a shaded highlight box and an
independently-positioned leader/label.** A single dot could only ever point
at one location — it could not show how much of the drawing a dimension
actually covers, and on a dense drawing a cluster of dots and their value
chips could easily overlap the very features they were meant to identify.

- **Drawing a new annotation now drags out a box** around the feature
  instead of a single click — or just click, for a sensible default-sized
  box centred on the click. Either way, a leader line and a numbered label
  appear automatically, offset into clear space beside the box.
- **The box, its four corner handles, and the label are all independently
  draggable** once placed — grab the box to move it, a corner to resize it,
  or the label to reposition it without touching the box at all. No mode to
  enter first; this works any time the plan isn't frozen.
- **The box scales with the drawing itself as it is zoomed**, so it keeps
  covering the same real feature at any zoom level — unlike the label,
  which deliberately stays a constant, readable size the way the old
  marker always did.
- Every marker placed under the old single-point model is upgraded
  automatically to a small default box in the same place, with its own
  independently-adjustable leader — nothing needs to be manually redrawn,
  though most will still want their box resized to actually frame the
  right feature.
- The printed customer report is unchanged for now — it still prints the
  simple numbered circle this replaces in the interactive editor.

### 0.13.0 — 2026-08-19

**A PMP created without a marker — or one whose marker landed in the wrong
place — could never be fixed.** "Add PMP manually" has always been useful
for a characteristic that isn't really a point on the drawing (e.g. a
general note), but there was no way back from it: no way to give it a
marker later, and no way to nudge an existing marker once placed, short of
deleting the PMP and starting over.

- **Any PMP's edit panel now shows its marker status, with a button to fix
  it** — "Place on drawing" for one with no marker, "Move marker" for one
  that already has one. Either puts the drawing into the same click-to-place
  mode used when creating a new PMP, except the next click updates that
  PMP's position instead of creating another one.
- Switching to a different PMP while mid-move cancels the move rather than
  leaving it silently pointed at whichever PMP "Move marker" was clicked on
  — otherwise a stray click on the drawing afterward would have moved the
  wrong PMP, or (worse) silently created an unrelated new one.

### 0.12.0 — 2026-08-19

**Creating a PMP and editing one are now the same form.** A characteristic
used to exist in two different shapes: a compact draft you filled in and
committed, then — once created — a fuller panel with sections (gauge and
frequency detail, photographs, an InspecVision scan) the draft never had,
under different field labels for the same values ("What is being
controlled" vs. "Characteristic"). Placing a marker, or clicking Add PMP
manually, now creates the real PMP immediately, with sensible defaults, and
opens the exact same panel used to edit any other one — nothing is unlocked
later, because there is no "later" left to unlock it in.

- **Deleted the entire separate draft form** — one panel, used for both.
  Every field that exists while editing now also exists the instant a PMP
  is created.
- **Result type (Actual value / Good / no good) can now be changed after
  creation.** It used to be fixed at the moment of creation, which is a
  moment that no longer exists — so this was a necessary consequence of
  unifying the form, not an independent decision. This also un-blocks a
  real dead end: a PMP created as "Actual value" could never attach an
  InspecVision scan (scans need "Good / no good"), with no way back.
- **The "Linked" risk-analysis option can now create a brand-new shared
  process FMEA row inline, from any PMP's own edit panel** — previously
  only available while a PMP was still being drafted; editing an existing
  one could only link to a row that already existed.
- "Cancel" on a just-created, still-blank PMP is now simply Delete, in the
  same characteristics table every other PMP is deleted from — there is no
  longer a distinct not-yet-real state for a separate Cancel to discard.

### 0.11.1 — 2026-08-19

**Fixed: a field that already held a real value — a default rating, a
previous reading — didn't clear when you started typing over it.** Clicking
in and typing just inserted at wherever the browser put the cursor, so
typing "8" into a severity field already showing "5" produced "58", not
"8" — indistinguishable, at a glance, from the value never having been
editable at all. Every field like this (severity/occurrence/detection
ratings, occurrences-on-drawing, nominal/upper/lower once a PMP already has
values) now selects its whole contents the instant it gains focus, so the
first keystroke replaces rather than inserts. Left alone on purpose: the
longer free-text fields (failure mode, effect, cause, control, description)
still work as click-to-edit-in-place, since select-all-on-focus there would
mean one stray keystroke could wipe a whole typed sentence.

### 0.11.0 — 2026-08-18

**A PMP's risk analysis and a process FMEA row used to be four disconnected
things that nothing kept in agreement.** Creating a characteristic filled in
its own embedded failure-mode fields; the FMEA page kept a separate,
step-scoped row with its own scoring; a shared template library held a third
copy; and a manual "Import existing per-PMP FMEA" button was the only bridge
between the first two — deliberately leaving the original in place once
clicked, so the two could silently drift apart forever after. The printed
control plan already showed the seam: "what we measure" and "what we
analysed" were two sections grouped by the same step headings with no
cross-reference between them.

This releases the model instead: **every PMP now carries exactly one of two
explicit kinds of risk analysis.** A **one-off** analysis is written
specifically for that PMP — for a check unique enough to this product and
this point in the route that sharing it would mean nothing (a specialised
coating check, a visual check for cracking or scuffing). A **linked**
analysis points at a shared process FMEA row that may be verified by several
PMPs at once (several dimensional checks all verifying "formed geometry" at
one press-brake step). A linked PMP's process step always comes from the row
it points at — never a field of its own — so the two cannot disagree; the
relationship is one row to many PMPs, never the reverse.

- **PMP creation and editing gained a Risk analysis section** with an
  explicit One-off / Linked choice. Linked offers either an existing process
  FMEA row or a compact inline form to create a new one on the spot, without
  leaving the drawing. One-off keeps today's failure-mode fields, now backed
  by a working knowledge-base picker (below).
- **Two independent actions on a one-off PMP:** *Promote to a process FMEA*
  turns it into a shared row other PMPs on this plan can link to; *Save to
  knowledge base* banks its wording for future plans. Either, both, or
  neither — a check can be genuinely unique to this plan while still worth
  remembering, or worth sharing within this plan without being proven enough
  to bank permanently.
- **Fixed: picking a knowledge-base entry could silently overwrite
  everything already typed**, severity/occurrence/detection included, a beat
  after the pick. Picking now only ever fills fields that are still blank;
  applying the suggested ratings, or replacing the line wholesale, are both
  separate, explicit choices.
- **The printed report's Control Plan and Process Risk sections now
  cross-reference each other** — a Risk analysis column on the control plan
  showing which failure line covers each characteristic (or that it is a
  one-off), and a Verified by column on the process risk table showing which
  characteristics back each failure line. The "no FMEA recorded" gap is
  raised per characteristic now, not once for the whole plan — a single
  well-covered characteristic could previously hide every other one that had
  nothing behind it at all.
- **Deleting a shared row that still has PMPs linked to it now asks first**,
  and un-links rather than orphans them — the affected PMPs fall back to a
  one-off analysis with that row's wording carried over intact, matching how
  removing a route step has always treated its FMEA rows.
- New defensive check: a PMP linked to a row that no longer exists (only
  reachable by hand-editing a record, not through the app itself) is now
  surfaced as a blocker on Review, with a direct way to re-link or drop back
  to one-off from the PMP's own edit panel.

### 0.10.0 — 2026-08-18

**Two annotation-flow fixes from real use.**

- **Fixed: the Nominal/Upper/Lower tolerance fields on an existing PMP could
  not accept a decimal point.** Typing "13.5" silently collapsed to "13" —
  the input re-derived its displayed value from the stored number on every
  keystroke, and `Number("13.")` is `13`, so the "." never survived long
  enough to type a second digit after it. Clearing a field also used to
  silently store `0` rather than "no value"; it now correctly stores nothing.
- **Unified how a characteristic's inspection frequency is set.** Creating a
  PMP used to offer a single "Inspection interval" dropdown, while editing an
  existing one separately offered a fuller multi-select "Check frequency"
  checklist (needed for AIAG-VDA-style compound frequencies, e.g. "twice an
  hour AND at shift start AND at material batch change") — two different
  controls for what looked like the same thing, because the second one was
  added later and the first was never retired. Creating a PMP now uses the
  same checklist editing already did, and writes directly to the field the
  printed control plan already treats as canonical — so a newly-created
  characteristic's frequency is real, saved data immediately, not something
  that only becomes correct after a save-and-reload round trip.

### 0.9.0 — 2026-08-18

**Once issued, the standard freezes but the evidence keeps growing.** Prompted
by a question the app's own explanation of itself raised: is an ISIR a
one-shot document built once and submitted for approval, or does the issued
record keep serving as the live controlled standard for the rest of the
part's production life? The answer settled the design: the latter. The route,
characteristics, tolerances and risk analysis an issued plan was judged
against stay frozen forever, exactly as before — but new evidence from
ongoing production can now keep landing on that same record, specifically so
Cpk and trend analysis can be tracked over the part's life instead of being
frozen at a single first-article sample.

- **New evidence — sample readings, CSV imports, manual checks, capability
  studies, InspecVision re-scans — can be added to an issued record.**
  Deliberately narrow: only *adding* opens up. Removing or editing any
  evidence already on the record stays exactly as locked as every structural
  field, matching the app's existing "orphans are cheap, destroyed evidence is
  not" rule for attachments and scan data.
- **A gauge study can be created *and filled in* after issue, not just
  created.** A capability study is built up over repeated trials as the
  physical R&R is actually performed — unlocking creation alone would have
  left a study that could never be completed once issued.
- **Re-running an InspecVision merge keeps working after issue** — the
  scenario this was built for: a part stays in production for months after
  its first article is approved, and the scan data should keep accumulating
  against the same controlled record the whole time.
- The lock banner and its wording now say correctly, wherever they appear,
  that the standard is frozen while evidence is not — previously every locked
  state read as "contents are frozen," which stopped being accurate the
  moment this shipped.

### 0.8.0 — 2026-08-18

**A record can no longer be issued while evidence is incomplete.** Prompted by
a real incident: a batch shipped without its 3D scan because the paperwork was
still the old Excel ISIR, a plain document with no way to refuse to be
completed — whether the gap got caught came down to someone remembering to
check under time pressure, which didn't happen. This is the point of building
software instead: it can refuse, where a spreadsheet never could.

- **"Issued" is blocked while any characteristic has missing or failing
  evidence** — the same "any failure blocks readiness" rule that already
  governs every other characteristic in this app, now actually enforced
  rather than only ever displayed.
- **Also blocked when a route step marked as needing a 3D scan has no
  characteristic covering it at all** — the deeper version of the same gap,
  and the one that likely matters most: previously invisible everywhere,
  because every existing check only ever asked "is this characteristic
  satisfied," never "does this step that needs one have one in the first
  place." The printed customer report used to silently drop such a step from
  the document entirely rather than showing a gap — fixed alongside this.
- **A password-gated override exists for genuine exceptions** — refused by
  default, same as the app's one other fail-closed mechanism (un-archiving);
  using it requires initials and is recorded permanently against the record,
  visible on its approval trail.
- Found and fixed a real bug while building this: the Review page's "What
  blocks issue" panel silently excluded InspecVision-verified characteristics
  from its evidence check, and never checked failing readings at all, for any
  characteristic type — it now shares the same underlying check as everywhere
  else instead of a second, narrower one that had quietly drifted.

### 0.7.0 — 2026-08-18

**Route templates can now be created and duplicated, not just edited.** Until now
the only way to make the single seeded template mean something specific was to
rename it in place — there was no way to start a second one from blank, only to
snapshot one from an already-built plan.

- **"+ New template"** starts a blank, named template, open and ready to build.
- **Duplicate** copies an existing template — fresh step ids, independent from
  then on — the fastest way to start a close variant of one that already exists.
- Templates carry a **free-text description**: what product type or production
  method the route is for, shown at the point of picking one to apply. Deliberately
  not a structured field or an automated match — which template applies is a
  judgement call, and the description is guidance for the person making it, not a
  rule the app enforces.

**A new shared Station Code Library** replaces free-text station codes — on both
the route step editor and the FMEA knowledge base's station rows — with a picker
onto one growable list, so "GI-01" always means the same real station wherever
it's picked. An inline "+ Add new code" covers anything not in the list yet, and
reuses a near-duplicate (different case, stray spacing) rather than creating a
near-twin. Seeded from the 29 real codes already in the standard route.

**Fixed a correctness gap the above made newly dangerous.** Re-applying a route
template preserved a plan's existing step ids — and with them, its FMEA rows and
PMPs — wherever a step's code matched, with no idea whether it was re-applying the
*same* template or a completely *different* one. Harmless while only one template
existed. The moment a second template reuses a code like "GI-01" for a different
process, applying it to a plan already running the first would have silently
attached the old step's history to an unrelated one. Applying a template now only
preserves ids on a genuine re-apply of the template already on the plan; a
different template does a clean replace, with a clear warning beforehand that
existing FMEA/PMP links on steps outside the new template will be orphaned — not
deleted.

**FMEA failure lines now carry their own reference number** (FM-01, FM-02…),
independent of route-step numbering. Previously the only number anywhere near a
failure line was its parent step's, printed once above the whole group — read at a
glance, that looks like the failure line's own number, which is the mix-up this
fixes. Numbers are assigned once, in the order rows are created, and never reused
after a row is deleted — so a number once shown or discussed keeps meaning the same
row. Shown on the FMEA page, the customer report's process-risk table and its
high-priority list in full, and the internal review screen's equivalent.

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
