# NWMS Quality Records — version history

## Versioning scheme

Semantic Versioning (MAJOR.MINOR.PATCH), shown in the app as **"Beta v0.27.0"** —
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

### 0.29.0 — 2026-09-04

**Annotation sizing is now four settings the user sets directly — font
size, line weight, arrow size and corner radius — replacing both the
earlier collective scale multiplier and the PDF export's own page-area
auto-calibration.**

Two rounds of trying to auto-derive the right size had both been reported
back as wrong on a real document, most recently with side-by-side evidence:
a critical PMP's label chip rendering as an illegible solid-colour blob on
screen, and the exported PDF sitting far too small next to a mockup built
by hand in Illustrator to show the intended proportions. The likely cause:
the source drawing is A2, but the PDF it was converted to reports as
A3-sized — so a formula that infers "how big should this be" from the
PDF's own page dimensions is reasoning from a false premise for this
document, and that mismatch cannot be detected from the PDF alone. There is
no way to out-guess this with a better formula, so sizing is no longer
guessed: all four values are real point sizes, set once per plan, applied
identically everywhere (the PDF export draws them as literal points; the
two on-screen surfaces convert the same numbers into their own viewBox
units via one fixed, universal ratio — never anything read from the
uploaded document's own reported page size).

Collapsing box border, label border and leader line into a single "line
weight" value (previously three independently-derived numbers) also closes
off a bug that had recurred twice already — the box and the label chip
quietly ending up different weights, no matter how carefully the formula
relating them was tuned. They cannot drift apart when there is only one
number feeding all three.

New settings icon on the drawing canvas (both the main view and the popped-
out window) opens a small panel with the four values and a reset-to-
defaults action.

### 0.28.1 — 2026-09-04

**Two follow-ups to 0.28.0's styling pass, both found by comparing the same
real record's rendering across surfaces rather than by inspecting one
surface alone.**

- **The label chip's border still wasn't the box's own weight, despite
  0.28.0's fix.** That release brought the box and the chip to the same
  base border width, but deliberately left the chip's border OUT of the
  critical 2x weight multiplier, reasoning the chip's new double border
  already carried that signal on its own — reported back, correctly, from
  a real screenshot: an SVG stroke renders centred on its own path, so an
  un-doubled chip border next to a doubled box border were never going to
  look equal regardless of their base values. The chip border now takes the
  exact same `width * weight` the box border does, in every case. That
  reopened the space problem the exemption existed to dodge — a critical
  chip's border is now visibly thicker, and a second border plus a real gap
  no longer fit inside the old chip height — so `LABEL_HEIGHT_RATIO` grew
  (1.9 → 2.6, and extracted into one shared constant, previously three
  separately-hardcoded copies) rather than shrinking the border back down.
- **The exported PDF and the on-screen drawing looked "very different" side
  by side**, per a direct comparison against a real record. Three separate,
  structural mismatches, not just differently-tuned numbers:
  - The label chip's fill was flat, near-opaque white in the PDF, versus a
    subtle tint of the PMP's own colour on screen — a genuinely different
    look, not a sizing difference. The PDF now uses the same colour tint.
  - The leader arrowhead was two thin open strokes meeting at a point in
    the PDF (a hollow chevron), versus a solid filled triangle on screen —
    so the PDF's arrowhead could never read as "solid" no matter how large
    it was drawn. Now drawn as a real filled triangle.
  - A critical PMP's `✳` suffix, visible on both on-screen surfaces, has
    never been drawn in the PDF export at all — it was silently using the
    bare reference. Now included, with one necessary difference: the PDF's
    font is WinAnsi-encoded and has no `✳` glyph (drawing it would throw
    and abort the export), so the PDF uses a plain `*` instead — same
    purpose, unavoidably different character.

### 0.28.0 — 2026-09-03

**Styling consistency pass on PMP annotations, plus a new double border for
critical characteristics.** Four reported issues, all in `leader-geometry.ts`'s
shared style system and its three consumers (the interactive canvas, the
printed report, the PDF export):

- **The PMP box's corner radius stretched into an ellipse on a non-square
  box.** A plain CSS `%` border-radius is relative to the box's own width
  for the horizontal radius and its own height for the vertical one, so a
  thin sliver of a box (a hairline slot or edge dimension) got a corner
  squashed along whichever axis was longer. Replaced with a radius derived
  from one fixed size independent of the box's own proportions, expressed
  as two different axis percentages via CSS's slash longhand so the two
  cancel out the box's own aspect ratio — the same rounding regardless of
  how stretched the box itself is.
- **The PMP box's border and the label chip's border were two different
  weights** (1.5 and 0.4) with no reason for the mismatch. They could not
  simply both become the box's own 1.5, though: verified on screen, not
  assumed, a 3-unit border (1.5 at critical weight) on a label chip only
  ~2.7 units tall consumed the entire chip, rendering as a solid blob with
  no visible fill. Both now share 0.45 instead — a real, visible change to
  the box's own border, not just the chip's.
- **Critical characteristics now draw a double border on the label chip** —
  a second, inset border, replacing "thicker single line" as the chip's own
  critical signal (the box itself keeps its existing 2x weight at critical
  unchanged). Getting the gap right took a second pass: a gap merely equal
  to the border's own width still rendered as one solid band, since an SVG
  stroke renders centred on its path; the two only read as separate lines
  once the gap exceeds the border width, confirmed by measuring the actual
  rendered geometry rather than trusting the arithmetic alone.
- **The leader arrowhead was too small as standard** — a chevron barely
  wider than the line it sat on. Raised on both SVG surfaces (the marker's
  own size, in multiples of the leader line's stroke width) and in the PDF
  export (`PDF_BASE_ARROW_SIZE` 2pt → 4pt).

### 0.27.3 — 2026-09-03

**The popped-out drawing window could show stale annotations after sitting
in the background.** Investigated a report of ghost PMP boxes appearing in
the popout after deleting every PMP, and of a PMP's box visibly shrinking
and moving as the annotation-size stepper was clicked. Extensive testing —
including against an exact, byte-for-byte copy of the real record pulled
from Dev — never reproduced either as a genuine data change: the stored
PMP positions and sizes never moved, no matter how the size stepper or
delete button were driven. Confirmed instead once the affected record was
retired for a fresh one that the problem was tied to that specific
long-lived browser session, not the app's handling of any record's data.

The most likely mechanism: a browser throttles a backgrounded tab's timers
and message handling, so a popout window left behind other windows for a
stretch could be sitting on a delayed queue of sync messages, showing
something out of date until the queue caught up. The popout now asks the
main window for a fresh full sync the moment it becomes visible or gains
focus again, rather than trusting a throttled queue to catch up on its own
— self-healing at exactly the point someone is about to look at it. Not a
confirmed fix for a bug that was never actually reproduced live, but a
real, low-risk hardening of a genuine gap in how a backgrounded popout
recovers.

### 0.27.2 — 2026-09-03

**A PMP's custom colour could jump to the wrong PMP.** Reported as "the
colours and shapes of the pmp annotations is changing... without any
input," certainly in the popped-out drawing window. The colour
`<input type="color">` in the editor panel had no `key`, so React reused
the same DOM node across a PMP selection change — a native colour dialog
fires several `input` events while it's being dragged, and if a different
PMP was selected before the dialog settled, a trailing event from the
abandoned drag could still land, applying to whichever PMP was *now*
selected rather than the one actually being edited. Fixed by keying the
input on the selected PMP's own id, so a stale event from an
already-abandoned picker has no listener left to reach.

Investigating this also turned up two related, independently real bugs:
the popped-out window's reconnect handshake never stopped retrying once
connected, quietly re-requesting a full state sync every 1.5 seconds for
as long as the window stayed open; and `DrawingCanvas`'s one-time
auto-fit-zoom could re-fire on a PDF sheet specifically, since `PdfSheet`
re-reports the page's aspect ratio on every container resize, and
floating-point drift between two of those reports was enough to look like
a genuinely new value — silently overriding a zoom level already set by
hand. Both fixed.

### 0.27.1 — 2026-09-03

**Two fixes to 0.27.0's annotation styling.** The PDF export's annotation
size was still keyed to the page's raw *width* — for a scanned image, its
pixel count treated as points outright; even for a real PDF, a landscape and
a portrait export of the very same A3 sheet came out two different sizes,
since width alone doesn't agree with itself across orientations. Replaced
with `pdfAnnotationStyle()` in `leader-geometry.ts`, calibrated to real
physical units: a 12pt font, 2pt lines (leader, box border and label border
together, as one figure), a 2pt arrowhead and a 5pt label radius, at 100% on
a sheet the physical size of A3 — scaled by page *area*, not width, so
orientation no longer matters, and scaled by the size stepper as one
uniform multiplier so every element grows together exactly proportionally.
The interactive canvas and printed report were untouched — their on-screen
sizing was already correct and wasn't part of this fix.

Also: a PMP's custom colour was being visually dropped the instant a
*different* PMP was selected — confirmed the underlying data was always
saved correctly; every drawn property (box, line, arrowhead, text) already
read the PMP's own colour regardless of selection except the label chip's
background fill, still hardcoded to a neutral tint whenever that PMP wasn't
the selected one, a leftover from before per-PMP colour existed. The chip
now always tints by the PMP's own colour, with selection shown as a
stronger tint rather than colour-vs-no-colour — fixed identically on the
printed report's own label chip, which had the same always-neutral fill.

### 0.27.0 — 2026-09-03

**Consistent, scalable drawing annotations, plus a per-PMP colour.** A PMP
marker (box, leader line, label, arrowhead) was drawn on three separate
surfaces — the interactive canvas, the printed report's drawing figure, and
the annotated-PDF export — each hand-tuned with its own numbers: reported as
"line weighting and radius scale... do not look consistent," and confirmed
by direct comparison — the canvas never distinguished critical from normal
on its leader line at all, its label border was keyed to *selection* rather
than criticality, and the report and PDF export each carried their own,
mutually inconsistent weights. `leader-geometry.ts`'s new `annotationStyle()`
is now the one place every line weight, border width, corner radius and
arrowhead size is derived from — one base scale, one critical/normal ratio
(a clean 2x, reconciled from the report's own prior numbers) — consumed
identically by all three surfaces, so they read as one coherent drawn system
rather than independently-tuned pieces. A new stepper on the Drawing & plan
page (next to the existing zoom control) adjusts that scale collectively,
persisted per plan, unaffected by the plan's own lock — it's a display/print
preference, not part of the standard being measured. PMPs also gain an
optional custom annotation colour (a plain colour-picker input, the first in
the app), layered on top of — never replacing — the criticality signal:
weight and the critical ✳ label suffix (now shown on the canvas too, not
just the printed report) stay purely criticality-driven regardless of what
colour is chosen, so "colour is never the only signal" stays true even for
a custom one.

### 0.26.0 — 2026-09-02

**Works Orders: repeatable production evidence against an issued plan.** A
plan is approved once — set, submitted with its first-article evidence,
issued — and that's always been the end of the story: the only way through
the lock was `amendPlan`, meant for when the standard itself changes. Real
production doesn't stop at first article; the same approved standard governs
every later run, and each one needs its own fresh capability/conformity
proof, tied to a real works order number that also appears in Kanban SPC and
InspecVision scan exports.

A Works Order is a new, independent record — its own page under **Works
orders**, its own provider/repository, its own tiny `open`/`locked`
lifecycle. It references an issued plan by id and holds only its own fresh
evidence (readings, CSV imports, manual checks, InspecVision scans,
photographs) against that plan's existing characteristics; the plan itself,
and its own original evidence, are never touched. Start one from an issued
plan's Customer approval page.

Finishing a run means generating its own **Capability / Conformity
Report** — a new, leaner document distinct from the ISIR: results,
capability and photographic evidence for that one run, without repeating
the process risk, drawing notes or sign-off sections the ISIR already
covers once. Generating it is a separate, explicit action from printing —
"Finalize & lock this works order" — after which the record locks the same
way an issued plan does. It can be reopened with the shared privileged
password (the same `PrivilegedGate` already used to un-archive a plan), so
end users can't casually go back and edit genuine results.

### 0.25.0 — 2026-09-02

**Failure lines no longer have a seeded starter set.** The 17 standard entries were a redundant second copy of the same content Station Rows already carries as the real, privileged standard — pointed out immediately after 0.24.0 shipped: "these should not exist at all since they will be in the station rows." Failure lines now starts empty; every line either gets typed by hand or captured from a specific record's own risk analysis. Already-provisioned Dev/Live data self-heals on next load — no manual data fix needed, and no local browser copy is left stranded with the old 17 either.

**Route templates gained a one-click "Reset to original template"**, alongside the existing "choose a different template" flow — reverts the route back to whichever template this plan actually started from (tracked per-plan already), rather than needing to re-find and re-pick the same one from a growing library of product/quantity-specific templates. Confirmed before it happens what's kept and what's dropped: steps whose codes still match keep their FMEA and PMP links (nothing unique was ever created for them), but any hand-edited wording on them reverts to the template's own, and steps added or no longer in the template — along with anything attached only to them — are dropped rather than silently kept half-consistent.

### 0.24.0 — 2026-09-02

**Failure lines are now scoped to the record they were captured on**, found within a day of publishing 0.23.0: opening the Library with nothing loaded showed every job's one-off captured lines, which reads as clutter and undermines "these belong to a specific record." Only the original 17 starter lines — nobody's specific job — always show; anything captured from a record now shows only while that record is open.

- **"Show all failure lines"** — off by default, ticking it restores the full cross-job list, so the reuse value ("did someone deal with this before, on a different job?") isn't lost, just opt-in rather than always-on.
- The existing wording search now doubles as that lookup: with "Show all" ticked, it searches every job's captured lines, not just the open record's own.
- Each line now carries a part-number badge (or "standard" for the starter set) alongside the fuller "captured from X" detail, so which ISIR/part a line came from is visible at a glance, not just on hover.

### 0.23.0 — 2026-09-02

**The FMEA knowledge base is now two genuinely different libraries, not one
idea hand-typed twice.** Station rows are the constant, company-wide
standard every new plan starts from — now privileged, only editable from
the Knowledge Base, by whoever has the password. Failure lines are for
whatever's specific to the record open — a one-off risk on an unusual
part — and stay open to anyone, same as before.

- **Station rows are now privileged**, the first genuinely server-enforced
  password check in this app: the QC API itself refuses the write, not just
  the browser's own UI. Split into their own storage
  (`data\station-fmea.json`) and their own endpoint (`PUT
  /api/library/station-fmea`), so they can be gated independently of the
  three collections that still aren't. Existing station rows already saved
  are carried across automatically the first time the service starts with
  this version — nothing to do by hand.
- Editing a station row now happens locally and stays local until an
  explicit **Save changes to the standard** click — a keystroke-driven
  autosave has nowhere to carry a password a gated write now needs, and
  this matches the same "no silent writes" rule the rest of this release
  applies everywhere else.
- **"Save as Failure line"** and **"Promote to a Station Row"** replace the
  old single "Save to knowledge base" button, both on the FMEA page's row
  editor and the PMP panel's one-off editor. Saving as a Failure line tags
  the entry with the record it came from, so it can be recognised as
  specific-to-a-job when someone browses the library later. Promoting
  never writes the shared standard directly — it stages a draft and hands
  the person to the Knowledge Base to actually finish and save it, same
  place every other station-row edit happens. A row seeded from a station
  row remembers where it came from, so promoting it defaults to *updating*
  that same entry instead of creating a near-duplicate.
- The 17 real failure chains behind Failure lines' starter set are no
  longer hand-duplicated in a second file — they're derived from the same
  station data Station Rows already used, so a correction made in one
  place is never stranded in the other again.
- A PMP itself still never belongs to either library, only the failure
  analysis underneath it does — unchanged, just made explicit: a PMP is
  always specific to the drawing it sits on.

### 0.22.0 — 2026-08-20

**The customer report now shows the same box-and-leader drawing the
workbench and the annotated PDF export both use**, instead of the older
plain numbered circle. All three now share the exact same positioning
maths (a common `leader-geometry.ts` module), so what an engineer places on
the drawing, what gets exported, and what the customer reads are always
the same picture.

- The report draws each characteristic's box, leader line and label exactly
  where it was placed on the sheet — full PMP reference text on the label,
  not just a number.
- This page has its own stricter rule, stated at the top of the file since
  the app was first built: colour is never the only signal, because it
  gets photocopied in mono and some readers are colourblind. The
  interactive canvas and the PDF export both mark a critical characteristic
  by colour alone, which is fine on a screen — here, a critical box, leader
  line and label are also drawn with visibly more weight and carry the same
  ✳ this app already uses everywhere else for "critical", so the
  distinction survives with the colour stripped out.

### 0.21.0 — 2026-08-20

**A drawing can now be exported with its annotations baked in as a real
PDF** — "Export annotated PDF" on the Drawing & plan page saves a new file
carrying the same boxes, leader lines and labels the interactive canvas
shows, for handing to Production Kanban so the shop floor can see what must
be controlled without this app open.

- **Genuine vector graphics, not a screenshot.** The annotations are drawn
  directly into the PDF's own page content, so the result stays sharp at
  any zoom and prints properly, the same way the source drawing already
  does — a source PDF's own pages are annotated in place; a plain
  image upload (a scan or photo, no PDF underneath) gets a new PDF built
  around it at the image's own full resolution, not the small preview used
  for the page-picker strip.
- **Verified by rendering the actual output back and checking pixels
  against the maths**, not just by eye: exported a real customer drawing
  with test markers, rendered the result, and sampled pixel colour at the
  exact expected position — the alpha-blended colour matched the formula
  to the last digit. Also checked a page carrying real PDF rotation
  metadata (found no real example of this among available drawings, so
  built one to test against): positioning and the label text's own
  upright orientation both came out correct.
- Only PMPs with a marker actually placed on the drawing are included, and
  only what a page shows — the same filter the canvas itself already uses.
  A plan with no drawing loaded has nothing to export from; every other
  combination (zero PMPs, a locked plan, multiple sheets) exports fine.

### 0.20.0 — 2026-08-19

**Two more sources feed the auto-filled import fields, for the parts of a
title block that are often never labelled at all.** Testing against a real
customer drawing found only drawing number and issue came back — the same
sheet had no "CUSTOMER:" label anywhere (it is the drafting company's own
drawing, from their side) and no separate "part number" label either.

- **A part number and a short description are now also read from the
  drawing FILE's own name** — "1394250-2-148-01- Transfer Rail 2992.5 Long
  Type 2.pdf" splits into a part number and a part title, independently of
  whatever the title block itself does or doesn't label. This works the
  same regardless of which CAD package exported the file, since the
  filename is chosen by whoever saved it, not the software.
- **The customer name now falls back to the company's own website**, when
  no "CUSTOMER:"/"CLIENT:" label exists on the sheet at all — a title block
  carrying "www.whittan.com" now fills in "Whittan" rather than leaving
  customer blank. Only used when the direct label search finds nothing, so
  an explicitly labelled customer field always wins where one exists.
- **The "New ISIR" wizard's Part title field is now filled in too**, the
  first field this reads that the Drawing & plan page doesn't have.
- Verified directly against the same real drawing this was built for: all
  five fillable fields (part number, customer, part title, drawing number,
  issue) now come back correctly, up from two before this release — only
  "Plan owner" is left blank, since nothing on a customer's drawing could
  reasonably say who at NWMS is accountable for the plan.
- These remain exactly what they have always been: a starting point in an
  ordinary editable field, never asserted as correct, and never applied
  over something already typed.

### 0.19.1 — 2026-08-19

**A real drawing, tested directly, exposed two separate problems: the sheet
could render silently clipped, and the title block parser could occasionally
read a wrong value instead of leaving a field blank.**

- **The drawing now fits the space it actually has.** It always rendered at
  100% width with no floor under how tall that made it, and "Fit drawing"
  just reset to that same 100% — on a wide enough window, a landscape sheet
  taller than the fixed drawing panel had its bottom silently cut off, with
  nothing to show anything was missing. Both the initial view and "Fit
  drawing" now compute the zoom that actually fits the sheet's real height
  into the space available. Verified directly against a real A2 drawing: at
  a shell width where 100% would have clipped it, it now opens at exactly
  the zoom the fit math calls for, confirmed pixel-for-pixel against the
  panel's actual bounds.
- **The title-block parser no longer searches the whole page** when the
  title block itself doesn't have a same-line match — found directly that
  this could match a label word used in an ordinary sentence elsewhere on
  the drawing ("...refer to Technical...") and return a meaningless
  fragment as the value. Every label pattern also gained a word-boundary
  fix: "ref" and "no" are common prefixes of ordinary words (refer,
  reference; note, normal, nominal), and neither was anchored to require a
  complete word.
- **The parser now also reads column-style title blocks** — a row of
  headers ("drawing number.", "issue.") with the actual values one or more
  rows below, each lined up under its own header by position rather than
  sharing a line with it. Found directly that a real customer drawing used
  exactly this layout and had no same-line match anywhere on the sheet.
- **A render that runs unusually long now times out with a visible message
  and a link to open the original PDF**, instead of an indefinite silent
  spinner or a blank sheet with no explanation. Investigated a render that
  initially took over two minutes on one real drawing; on a clean retry it
  rendered in under a quarter of a second every time, so this looks to have
  been this session's own load rather than a property of that file — but
  the timeout stays in either case, since a render that genuinely never
  returns is a real possibility worth guarding regardless of cause.

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
