# NWMS ISIR / Quality Records — Plan & Data Model

Status: **draft, awaiting Dave's decisions (Section 7) before Phase 0 starts.**
Written: 2026-08-14, from `NWMS-ISIR-app-kickoff-prompt_2.md` plus the real reference documents found alongside it in Downloads.

This is the response to the kickoff brief's Section 8: what I read, what's wrong or missing in the brief itself, the data model, the module map, the Phase 0 breakdown, and the decisions I need before writing any code. Nothing has been built. Treat this file, not the chat reply that points here, as the source of truth — same pattern as `NWMS Bespoke Platform - Proposal.md` and the Commercial CRM requirements doc.

---

## 0. Reference material — what I found and read

The brief's Section 8 asked me to request reference material before doing anything else. Before asking, I checked Downloads, since that's where the kickoff prompt itself was — most of it was already sitting there.

| Item | Status | Detail |
|---|---|---|
| `QCP-1394250-2-100_QC_Plan.docx` | **Found, read in full** | Real, dated, in-progress quality control plan — see Section 1 |
| `QCP-1394250-2-100_Inspection_Workbook.xlsx` | **Found, read in full** | Companion workbook, 7 sheets — see Section 1 |
| `Whittan Packing and Despatch Process.docx` | Found, **not yet read** | Likely resolves RFI-08 in the QC Plan (packing spec). Low priority — I stopped here rather than read everything in Downloads unasked. Say the word and I'll go through it. |
| `Web-Inspecvision-Planar-Brochure-May-21 (1).pdf` | Found, **not read** | Marketing brochure — brief already gives the exact real export column list (Section 4.4a), so a brochure adds little. Skipped. |
| `ISIR Report Builder — turn inspection workbooks into print-ready reports.pdf` | Found, **could not open** | This machine has no PDF text-extraction path available (no `poppler`, and Office COM automation fails in this environment — see note below). The title alone is worth asking about: is this a tool you found/evaluated, or something you or I wrote earlier? It may change the plan. |
| Corrected historical ISIR workbook (the one with the 50% phantom-failure result) | **Not found** | The QCP files above are a fresh draft, not that. See Section 1 — I think these are two different things and want to confirm before assuming. |
| Annotated drawing PDF | **Not found** | Still needed |
| Real InspecVision CSV export | **Not found** | Still needed |
| Real Kanban compliance CSV export | **Not found** | Still needed |
| `drawing-compliance-dashboard-prompt.md` (Documents\Claude root) | Found, read | A dashboard-widget-shell spec addressed to a *different* project ("the drawing-compliance-checker project's assistant"). Flagging in case it was meant for here, but I'm not assuming that — see Section 3. |

Three copies of the kickoff prompt exist in Downloads (no suffix, `_1`, `_2`) — I diffed them, they're byte-identical, so there's no version drift to reconcile. Working from `_2` as you pointed me to.

**Note on tooling:** I tried Excel/Word COM automation first to read the `.xlsx`/`.docx` properly; it failed with a COM `QueryInterface`/`TYPE_E_ELEMENTNOTFOUND` error in this environment (no interactive Office session available to script against), and left three orphaned background EXCEL/WINWORD processes, which I've cleaned up. I fell back to parsing both files directly as ZIP/XML (which is all `.xlsx`/`.docx` are under the hood) — no Office dependency, worked cleanly. Same trick will work for any future spreadsheet/Word reference material without needing Office automation. PDFs are the one format I have no reliable extraction path for on this machine right now.

I have **not** yet looked at the Planner's or Tool Room's actual source files (`sage-bridge.ps1`, `tool-room-bridge.ps1`, `index.html`, CSS) — I know their locations and architecture from memory, confirmed both still exist:
- `C:\Users\dave\Documents\Codex\NWMS Weekly Delivery Planner`
- `C:\Users\dave\Documents\Codex\Tool Room Job Manager`

I'll read the actual files (design tokens especially) once we're closer to Phase 0 build, as the brief asks — no point doing it now while the shape of this app is still moving.

---

## 1. The big finding: the real QCP-1394250-2-100 documents don't match the brief's worked example

The brief's Section 3 worked example (part `1394250-2-100-02`, customer Whittan, 14 characteristics `PMP1`–`PMP14`) is the same drawing and part as the real `QCP-1394250-2-100` documents I found — same drawing number, same issue, same "Transfer Rail 100×75×3×2920 (SKMX Racking)" description, same 19.3kg weight, same material spec. But the real documents are **richer and structured differently**:

| | Brief's Section 3 | Real `QCP-1394250-2-100` (dated 10/08/2026, DRAFT) |
|---|---|---|
| Characteristic count | 14 (`PMP1`–`PMP14`) | **52 balloons** |
| Ref format | `PMP` + number, prefix configurable | **Plain integer**, no prefix at all |
| Critical flag | Boolean | **6-value `Class`**: General / CRITICAL / Material / REF (internal) / ATTRIBUTE / CRITICAL (attribute) |
| Grouping | Not modelled | **`Group`**: Profile / Length / Station / Aperture / Cross-position / Geometry / Finish / Orientation / Reference / Material |
| Process-step coding | Proposed lookup: `A–F` (Material Receipt / First Off / Operator Change / In Production / Last Off / QA Final) + `GI, 1X/S, 2X/S, 1X/H, 2X/H, MC` | Actually uses **`Gate 0–4`** (Goods-in / Flat inspection / Press-brake setup+first-off / Final inspection / Pack+despatch) plus router-style **Op numbers** (10, 20, 25, 30, 35, 40, 50, 60), with free-text frequency/method/control fields |
| Open-question tracking | Not modelled | **RFI tracker** — 8 open clarification questions to Whittan (RFI-01…RFI-08), several characteristics explicitly marked provisional pending an RFI answer |
| FMEA | Full AIAG-VDA 7-step required | **Not present anywhere in the real package** — see Section 3.2 |

My read: the brief's `PMP1`–`14` table is an illustrative simplification (maybe a compressed retelling of the real defective historical submission), while what's sitting in Downloads is your team's actual, current, in-progress re-plan for this exact part — last touched four days ago, still marked `DRAFT — for internal approval`. It's also a *third* thing distinct from both: it isn't the "corrected workbook" the brief says it'll give me either, because every result cell in its FAIR sheet is empty (see Section 1.1). So there appear to be three separate artefacts around this one part:

1. The brief's own `PMP1`–`14` retelling — illustrative, not a real file.
2. The real, historically-flawed submission with actual measured numbers (the 50%-failure one) — **not yet located**, still needed from you if we want the Phase 0 exit test to mean anything concrete.
3. The real `QCP-1394250-2-100` planning package I read — a forward-looking re-plan, not filled in yet.

**I'd recommend building the data model against #3 (the real 52-balloon register) as the primary fixture**, since it's real, current, and far more demanding than the illustrative example — anything that handles 52 balloons with 6 classes, provisional-pending-RFI status, and Gate-based control cleanly will handle the simpler 14-item version for free, but not vice versa. That's the first thing I need your call on (Section 7).

### 1.1 Confirms two of the brief's defects are real, live, right now

Not hypothetical — I found live instances of two of the brief's Section 5 defects sitting in your current draft:

- **Defect #3 (floating-point noise):** the SPC Log sheet's worked I-MR example shows moving-range values of `0.0999999999999943` and `0.200000000000003`, and a Cpk of `1.15306666666672`. This is Excel's own float arithmetic leaking into a cell a human is meant to read. Confirms the "round for display, never for storage/comparison" rule in Section 4.4 below is worth the trouble.
- **Defect #1's cousin:** the FAIR sheet's `Result summary` cell currently reads `PASS (of results  0 pass)` — a template formula reporting an overall PASS against zero filled-in results. Same family of bug as the phantom 50%-failure case: a rolled-up status that doesn't honestly reflect an incomplete state.

### 1.2 Genuinely new domain concepts the real documents surface

The brief's domain model (Section 3) doesn't cover these, and they came up doing real work on a real part, not from a generic PPAP checklist. I think they belong in the data model:

- **RFI / clarification tracking.** Several characteristics are explicitly provisional — e.g. balloon 4 (bend angle, critical) is "treat as critical *pending RFI-01*", balloon 45 (twist) has a `TBA` limit *pending RFI-02*. A characteristic needs to be able to point at an open customer clarification and the submission-complete check needs to treat "still waiting on an RFI" the same way it treats an unmapped balloon — as a blocker, not a silent gap. This is a natural extension of the brief's own "every balloon must map to a control plan row" rule (defect #4), just for a different kind of incompleteness.
- **Records retention.** The QC Plan's Section 14 requires **≥10 years** retention on goods-in records, scanner reports, check sheets, SPC charts, NCRs, despatch notes — and *life of product* for the FAIR pack itself — "because racking is safety-related product." The brief's immutability rule (Section 6) only explicitly covers the issued *submission*; the real requirement is broader — every record type in that table needs the same non-destructive, append-only treatment, not just the final document.
- **Nonconformance / NCR.** Section 11 of the QC Plan requires: red-tag and quarantine, an NCR raised the same shift, containment scope traced back to "the last green check," and — importantly — **written concession approval from Whittan Technical only, no verbal acceptances**, plus a 24-hour escape-drill notification if suspect product may have shipped. This is a real gap worth flagging specifically because of what's in memory already: **Kelly (recently joined) is separately building NCR/root-cause/SPC/cost-of-quality structure for NWMS.** I don't want to design a second, competing NCR system here without knowing how it's meant to relate to hers — see Section 7.
- **Check fixture + multi-characteristic single-event results.** Section 7 of the QC Plan describes a go/no-go attribute fixture (drop the rail in, pins gate every critical position plus angle limit blocks at once). One fixture-drop produces **one pass/fail result covering many balloons simultaneously**, not one reading per characteristic. The brief's attribute-vs-variable split (domain primer) doesn't quite capture this — it's not just "this one characteristic is go/no-go," it's "this one inspection *event* yields results for a whole set of characteristics at once." I've modelled this in Section 4 as a `MeasurementSource` that can fan out to many `Measurement` rows, same mechanism the scanner import already needs.
- **Batch/shift check sheets as first-class records.** The real package has a **Flat Check Sheet** (Gate 1, one per nest program per coil — date/operator/program/coil header plus a fixed checklist) and a **Formed Check Sheet** (Gate 2 first-off, *plus* an hourly repeating log: time, fixture drop P/F, worst angle, key dimensions, operator, notes — this is literally where the SPC log's raw data comes from). These are shop-floor records in their own right, with their own retention requirement, not just a UI screen for entering `Measurement` rows. I've given them their own entity (`CheckSheet` / `CheckSheetLogEntry`) rather than folding them silently into "manual entry."
- **Coil-centred traceability.** Section 10's chain is `coil ID → goods-in record → nest/program+date → flat batch → brake batch/shift → gate records → despatch note/C of C`. The brief only mentions coil ID as a column inside the Kanban compliance CSV (Section 4.4b); in practice it's the spine the whole traceability chain hangs off. I've made `Coil` and `Batch` first-class entities rather than CSV columns.
- **Gauge R&R / MSA.** Section 6 of the QC Plan calls for a formal Gauge R&R study (10 parts × 3 operators × 3 trials, <10% GRR to pass) and an Attribute Agreement study (2 operators × 20 parts, 100% agreement required) before the fixture and caliper methods are trusted. The brief's gauge register (Section 4.5) only covers calibration due dates. I don't think the app needs to *run* these studies, but it may need to *hold the evidence* (pass/fail, %GRR, a report attachment) so a characteristic's stated method can point at a completed study. Scoping question in Section 7.

---

## 2. Where this sits relative to the Bespoke Platform

Worth being explicit about, since it affects almost every other decision below.

The Bespoke Platform proposal (`NWMS Bespoke Platform - Proposal.md`) currently has **no Quality/ISIR domain or phase** — I grepped it to check. Its phased roadmap runs infra → design system → login/permissions/data/comms/tasks → sales/design-engineering/planning/production/dispatch/accounting. Quality isn't in that list yet. It's also still blocked on Phase 0 (the Linux VM isn't provisioned, no Sage200 API access).

The Commercial CRM (requested three days ago) hit exactly this situation and the resolution was: **build fast on the proven Planner/Tool Room stack (PowerShell/vanilla JS/Access) now, deliberately using their lighter engineering standard rather than the Bespoke Platform's heavy one, with the explicit understanding that this POC becomes the functional spec for a proper Bespoke Platform phase later** — same relationship the Planner itself has to the Bespoke Platform's dispatch phase.

This kickoff brief reads like it wants that same POC-stack-now pattern (Section 2: "built on the same stack as the Planner and Tool Room Job Manager") — but its own "Code standard — non-negotiable" section (Section 2 of the brief) asks for the *heavy* standard word-for-word close to what's written for the Bespoke Platform specifically: composable architecture, comprehensive WHY-and-WHAT annotation, no shortcuts, real tests, clean git from commit one. That standard was previously scoped deliberately narrowly — *only* the Bespoke Platform codebase — precisely so the Planner/Tool Room/CRM POCs could stay fast and disposable.

I don't think this is a mistake in the brief so much as a genuine, undecided question: **do you want this specific app to be the first POC-stack project held to the full standard, or should it follow the CRM's lighter-now/heavier-later pattern?** Either is defensible — quality records going to a customer is a reasonable place to argue for the higher bar from day one, and it's also the first place git-from-commit-one would show up outside the Bespoke Platform. But it's a real fork in how Phase 0 gets built, not a detail — see Q2 in Section 7.

---

## 3. Other things worth raising before I start

1. **PFMEA isn't in the real QC package at all.** The real `QCP-1394250-2-100` risk approach is entirely control-plan + gates + SPC + RFI — there's no FMEA anywhere in it, not even a stub. That might just mean it lives in a separate file I haven't seen, or it might mean full AIAG-VDA 7-step PFMEA (brief Section 4.3) is genuinely new practice, not a documented-elsewhere-but-omitted-here thing. If it's new practice, there's no existing failure-mode/cause/control content to seed the "quick-text library" from, which changes how much Phase 1 FMEA work actually is — worth knowing before I estimate it. Is there an existing FMEA for any NWMS part I should look at, or is this genuinely greenfield?
2. **The drawing-click-balloon-placement UI is a lot of Phase-0 weight for 52 balloons.** The brief's Section 4.1 flow (click a point, type ref/description/nominal/tolerance/critical, per balloon) is the right long-term UI, but building and then hand-placing 52 balloons through it is a slow way to prove the walking skeleton. Your team already produces exactly the register I read, by hand, in a spreadsheet, before the drawing UI would exist. I'd suggest Phase 0 support **importing a characteristic register from a spreadsheet/CSV** as an equal or even first ingest path, with the drawing-balloon UI following once the evaluation/reporting core is proven — not instead of it, just not gating the walking skeleton on it. Flagged as a recommendation, not baked into the Phase 0 breakdown below yet.
3. **The brief's frequency/control-location code table doesn't match real usage.** Section 4.2's proposed lookup (`A–F` locations, `GI/1X/S/2X/S/1X/H/2X/H/MC` frequencies) isn't what the real control plan uses — it uses Gate 0–4 plus free-text frequency/method/control fields (see Section 1 table). I'd rather model frequency/control as free text with an extensible lookup seeded empty, rather than build out the brief's specific code table against a convention that doesn't match what you're actually writing. Said plainly in Section 4.
4. **`drawing-compliance-dashboard-prompt.md`** — found sitting in the Documents\Claude root, addressed to "the drawing-compliance-checker project's assistant," which doesn't sound like this project. I haven't assumed it applies here. If you want its dashboard-widget mechanics (show/hide, drag-reorder, resize, per-widget zoom) ported into this app's future dashboard, say so and I'll treat it as an input for a later phase — but I'm not pulling it in on my own guess.
5. **Everything else in the brief I checked against real usage held up well** — the signed-limits tolerance rule, the missing-≠-failing rule, at-limit surfacing, provenance-on-every-record, the scanner cross-check-don't-trust rule, the file-drop-first integration approach. No pushback on any of those; the real documents make them look more necessary, not less.

---

## 4. Data model

Entities below are grouped by concern. `PK`/`FK` noted inline; full audit trail (`AuditEvent`: entity type/id, changed-by, changed-at, field, old value, new value) applies to every mutable entity via the domain layer, not repeated per-table below.

### 4.1 Tolerance and unit handling — spelled out, per the brief's own requirement

This is the part most likely to silently pass a bad part if it's wrong, so being explicit:

- **Data entry captures two non-negative magnitudes**, not a signed pair directly — `ToleranceUpperMagnitude ≥ 0` and `ToleranceLowerMagnitude ≥ 0`. This matches both the drawing convention (`+0/-2`) and the real Register/FAIR sheets' own `Tol +` / `Tol −` columns exactly — confirmed against real data, e.g. balloon 8 (overall length): `Tol + = 0`, `Tol − = 2`.
- **The domain layer derives canonical signed limits** at the point a characteristic is confirmed, and stores them (not recomputed ad hoc on every evaluation):
  `TolLower = −ToleranceLowerMagnitude`, `TolUpper = +ToleranceUpperMagnitude`.
  - `±0.5` → magnitudes `(0.5, 0.5)` → limits `(−0.5, +0.5)`
  - `+0/−2` → magnitudes `(0, 2)` → limits `(−2.0, 0.0)`
  - `+1/−0` → magnitudes `(1, 0)` → limits `(0.0, +1.0)`
- **Attribute characteristics** (`Unit = "attribute"`) skip numeric tolerance entirely at the type level — `Measurement.AttributeResult` (Pass/Fail) is the only legal result field; `RawValue`/`Deviation` are structurally unavailable, not just conventionally unused. This is what stops defect-type "twelve readings of exactly 3.00mm" (brief Section 3) from recurring — a variable reading can't be entered against an attribute characteristic at all.
- **Evaluation is always computed, never stored as an independent field:**
  - `Deviation = round(RawValue − Nominal, 3)`
  - `Result = Outstanding` if `RawValue IS NULL` (never Fail — defect #1)
  - `Result = Pass` if `TolLower ≤ Deviation ≤ TolUpper`, else `Fail`
  - `AtLimit = true` if `Deviation = TolLower OR Deviation = TolUpper` — surfaced as its own flag, never folded silently into Pass (defect #12)
  - `PercentToleranceConsumed = |Deviation| / (Deviation < 0 ? |TolLower| : TolUpper) × 100`
  - Full precision is stored; rounding happens only at display/report time — this is the direct fix for the float-noise bug confirmed live in your own SPC Log (Section 1.1).
- **Unit lives on the Characteristic**, and every rendered value anywhere (UI, Excel, PDF) is required to pull it from there alongside the number — no template is allowed to print a bare number. This is what stops the "Bend Radius" label on an angle value (defect #5) from being possible rather than just discouraged.

### 4.2 Core entities

**Part** — `PartNumber` (PK), `Description`, `CustomerId` (FK), `MaterialSpec`, `WeightRef`, `RouteSummary`.

**Customer** — `Name` (PK), `CharacteristicRefPrefix` (nullable — real usage has *no* prefix, so this must be allowed empty, not just configurable-but-required), `ReportFormatPreference`.

**DrawingRevision** — `Id` (PK), `PartId` (FK), `DrawingNumber`, `Issue`, `IssueDate`, `SourceFileRef`, `IsCurrent`. A part points at its current revision; prior revisions stay linked for history.

**Characteristic** — `Id` (PK), `PartId` (FK), `IntroducedOnDrawingRevisionId` (FK), `Ref` (e.g. `8` or `PMP03` depending on `Customer.CharacteristicRefPrefix`), `Group` (lookup, seeded: Profile/Length/Station/Aperture/Cross-position/Geometry/Finish/Orientation/Reference/Material — extensible), `Description`, `Entity`/`Datum`/`Type` (optional — mainly scanner-sourced geometry), `Nominal`, `ToleranceUpperMagnitude`, `ToleranceLowerMagnitude`, `TolUpper`/`TolLower` (derived, see 4.1), `Unit` (mm/deg/attribute/other), `Class` (lookup, seeded: General/Critical/Material/Reference-Internal/Attribute/Critical-Attribute), `IsDerived` (bool — e.g. balloon 7's lip-gap proxy) + optional `DerivationNote`, `Instances` ("Places"), `MeasurementMethod`, `EquipmentId` (FK, nullable → Gauge), `BalloonX`/`BalloonY` (nullable), `Status` (Confirmed / ProvisionalPendingClarification), `OpenClarificationId` (FK, nullable), `ConfirmedBy`/`ConfirmedAt` (human-confirmation provenance for anything AI-assist proposed).

**CharacteristicRevisionDecision** — `CharacteristicId` (FK), `DrawingRevisionId` (FK), `Action` (Unchanged/Modified/Retired/New), `DecidedBy`, `DecidedAt`, `PriorValuesJson`. Exists specifically to satisfy the brief's "force a decision on every existing characteristic when the issue changes" rule (Section 4.1) with an actual audit record behind it.

**Clarification** ("RFI") — `Id` (PK), `PartId` (FK), `Code` (e.g. `RFI-01`), `Question`, `ProposedPosition`, `CustomerResponse` (nullable), `CustomerResponseDate` (nullable), `Status` (Open/Answered/Superseded), `RaisedBy`/`RaisedAt`. A characteristic with `Status = ProvisionalPendingClarification` points here; submission-complete check blocks on any open one, same severity as an unmapped balloon.

### 4.3 Process / control plan

**Gate** — `Id` (PK), `Code` (seeded 0–4, extensible per customer/part rather than hardcoded), `Name`, `Description`.

**ProcessStep** — `Id` (PK), `PartId` (FK), `OpNumber` (free integer, real usage is 10/20/25/30/35/40/50/60 — not contiguous), `Name`, `Machine`, `GateId` (FK, nullable).

**ControlPlanRow** — `Id` (PK), `ProcessStepId` (FK), `CharacteristicIds` (many-to-many — a characteristic can appear on rows at multiple gates, e.g. a starred cross-position checked flat *and* formed), `SpecificationText`, `MethodGaugeText`, `FrequencySampleText`, `ControlText` (free text/lookup: Verification/Setup approval/100%+SPC/Attribute+p-chart/SPC(I-MR)/Sample/Audit — seeded from real values, not the brief's proposed A–F/GI/1X table, see Section 3.3), `ReactionPlanText`, `RecordTypeId` (FK → what record this generates).

Submission-complete check (brief Section 4.2/5.4): every `Characteristic` must appear in at least one `ControlPlanRow`, and every `ControlPlanRow` with characteristics must have `Measurement` rows or an explicit `N/A` + justification.

### 4.4 Measurement

**Which source feeds which characteristics** (clarified by Dave, 2026-08-14): this isn't ad hoc per part, it follows the Gate split directly. Flat-stage characteristics (Gate 1 — the Length/Station/Aperture groups in the real register, the equivalent of the brief's `PMP1`/`PMP2`) are covered end-to-end by the InspecVision optical scanner; its own export **is** the file that gets imported — Dave's own working name for it is "the SPC file," since it's the raw material the SPC log is built from, but it's the same file as brief Section 4.4a, not a separate format. Formed-stage characteristics (Gate 2+ — Profile/Cross-position groups, the brief's `PMP3` onward) are the ones that get manually balloon-placed on the drawing, and their **measured values** come from the Kanban compliance module's CSV export (brief Section 4.4b) wherever a characteristic maps onto one of its fixed `a`–`h`/Square/Bow/Twist columns — confirms the brief's own "map `a`–`h` to characteristics per part code" requirement rather than adding a new one. Characteristics that map to neither — gauge-based (poka-yoke / go-no-go fixture) or visual checks (damage, scratches, cracking) — fall to manual entry (brief 4.4c), which is where the reference-evidence requirement below comes from. Kanban import itself is still Phase 2 per the brief's own Section 7 (Phase 0 explicitly excludes it) — this is the target steady-state, not a request to pull it earlier.

**MeasurementSource** — `Id` (PK), `Type` (Scanner/KanbanCompliance/Manual/FixtureDropCheck), `ImportedFileName`, `ImportedFileChecksum`, `ImportedAt`, `OperatorText`, `GaugeId` (FK, nullable). One source can produce many `Measurement` rows — this is the mechanism for both the scanner import (one file → many readings) and the fixture drop-check (one event → many characteristics' results at once, Section 1.2).

**Measurement** — `Id` (PK), `CharacteristicId` (FK), `InstanceNumber` (generated, never typed — defect #6), `SourceId` (FK), `RawValue` (nullable — null means not-yet-measured, never coerced to Fail), `AttributeResult` (nullable Pass/Fail, attribute characteristics only), `PartSerial`/`SampleLabel` (e.g. `P1`/`P2`/`P3` for a 3-part FAIR), `WorksOrderRef` (nullable — null flags the reading as untraceable per brief 4.4a, blocks submission until attached), `MeasuredAt`. `Deviation`/`Result`/`AtLimit`/`PercentToleranceConsumed` are computed, not stored (Section 4.1).

Report-time rollup: where a characteristic has multiple instances, the FAIR/ISIR report shows the **worst-case instance** per characteristic (confirmed as real convention — every multi-instance row in your actual FAIR sheet is annotated "[n places — worst case]"), computed fresh from the full set of `Measurement` rows at render time. The full per-instance data is never discarded even though the report rolls it up.

#### 4.4.1 Reference evidence / acceptance standards (added 2026-08-14, per Dave)

Gauge-based and visual checks need more than a pass/fail convention — an inspector doing a poka-yoke/go-no-go gauge check, or a visual check for damage/scratches/cracking, needs to know **what a pass actually looks like**, not just read a tolerance number. This extends brief Section 4.6 (quality notes/evidence) from purely retrospective (a note logged after an inspection) to also prospective (a standard attached to the check itself, before any inspection happens). It's exactly what the real QC Plan's RFI-05 is trying to pin down in words right now ("is minor crazing on the outside radius acceptable? Accept crazing, reject flaking/pick-off") — a reference photo pinned to that RFI once Whittan answer it is a direct, concrete example of this entity.

**QualityNote** — `Id` (PK), `AttachedToType` (Characteristic / MeasurementMethod / Submission / WorksOrder / Batch — matches brief 4.6's "against a submission, a characteristic, or a works order," extended to the method itself), `AttachedToId`, `Kind` (Note / AcceptanceStandardImage / InspectionEvidencePhoto), `Text`, `FileRef` (nullable — the image/diagram itself), `CreatedBy`/`CreatedAt`. Immutable once the `Submission` it's attached to is issued, same rule as everything else in Section 4.10.

Attaching at the `MeasurementMethod` level (not only per-`Characteristic`) means one "visual check for bend-zone galv crazing" reference photo gets written once and reused by every characteristic that shares that method, instead of the same image being pasted onto four-plus balloons individually. Worth confirming this default is right rather than always-per-characteristic, but it's a small enough call that I've modelled it this way rather than stopping to ask.

### 4.5 Batch / shift records

**CheckSheet** — `Id` (PK), `Type` (Flat/Formed/…, extensible), `PartId` (FK), `Date`, `OperatorText`/`StaffId`, `ProgramRef`, `CoilId` (FK), `GateId` (FK), plus a fixed checklist (child rows: item text, entry, sign).

**CheckSheetLogEntry** — `CheckSheetId` (FK), `Time`, values against tracked characteristics, `OperatorText`, `Notes`. This is the hourly in-process log (Formed Check Sheet) that feeds SPC directly — each logged value is also a `Measurement` row, tagged with its originating log entry for provenance.

### 4.6 Traceability

**Coil** — `Id` (PK), `CoilIdentifier`, `CertificateRef` (EN 10204 3.1), `ReceivedAt`, `ThicknessCheckText`, `SurfaceConditionText`.

**Batch** — `Id` (PK), `PartId` (FK), `CoilId` (FK), `NestProgramRef`, `BrakeProgramRef`, `Date`. Threads the real traceability chain: goods-in → flat batch → brake batch/shift → gate records → despatch (QC Plan Section 10).

### 4.7 SPC / capability

**SpcSeries** — `Id` (PK), `CharacteristicId` (FK), `ChartType` (seeded `I-MR`, the real convention — not X̄-R), `TargetCpkCritical` (seeded 1.67), `TargetCpkGeneral` (seeded 1.33). Cp/Cpk/UCL/LCL/sigma are computed on demand from tagged `Measurement` rows, never stored as a snapshot — direct fix for defect #3 and the live float-noise bug in Section 1.1. Satisfies defect #10 (an SPC claim on a control-plan row must have real capability data behind it, computed, or the claim is refused).

### 4.8 Gauges and measurement system evidence

**Gauge** — `AssetId` (PK), `Description`, `CalibrationDueDate`, `CertificateRef`.

**GaugeStudy** — `Id` (PK), `GaugeId` or `MethodDescription`, `Type` (GaugeRR/AttributeAgreement), `StudyDate`, `ResultPercent`, `Pass`, `EvidenceFileRef`. Scoping open — Section 7.

### 4.9 Nonconformance (deliberately thin pending your answer — Section 7)

**NonconformanceFlag** — `Id` (PK), `RaisedFromMeasurementId`/`CheckSheetId` (FK), `BatchId` (FK), `GateCaught`, `ContainmentScopeText`, `Status`, `ExternalNcrRef` (nullable — for linking out to Kelly's system once it exists).

### 4.10 Submission

**Submission** — `Id` (PK), `PartId` (FK), `DrawingRevisionId` (FK), `State` (draft → in_progress → ready_for_review → issued → superseded), `RevisionNumber`, `PreviousSubmissionId` (nullable, self-FK), `IssuedAt`, `InspectorApproval`/`CustomerApproval` (fields — blocked from being blank on issue, defect #11), `OutstandingItemsText` (generated, never hand-typed).

Immutability is enforced at the application layer: once `State = issued`, no `Measurement`/`Characteristic` row it references may be further mutated — a correction creates a new `Submission` revision instead, per the brief's own state-machine rule (Section 6). Not proposing full event-sourcing for Phase 0/1 — a guard in the write path is proportionate at this scale.

---

## 5. Module / layer map

Following the brief's Section 6 directly, made concrete:

```
/domain
  /characteristics    Characteristic, ToleranceEvaluator, UnitTypes, CharacteristicRevisionDecision
  /clarifications     Clarification (RFI), provisional-status rules
  /control-plan       ProcessStep, ControlPlanRow, Gate, completeness checks (defect #4)
  /measurements       Measurement, MeasurementSource, DeviationCalculator, InstanceNumberGenerator
  /spc                SpcSeries, CapabilityCalculator (Cp/Cpk/UCL/LCL — I-MR)
  /gauges             Gauge, GaugeStudy, CalibrationRule
  /traceability       Coil, Batch, WorksOrderRef
  /check-sheets       CheckSheet, CheckSheetLogEntry
  /fmea               [Phase 1] FmeaRow, ApTable (data, not code), QuickTextLibrary
  /submission         State machine, revision/diff, OutstandingItemsBuilder
  /audit              AuditEvent, ChangeRecorder
/ports                Interfaces only: IRepository, IDrawingRenderer, IScanImporter,
                       IKanbanImporter, IPlannerConnector, ISageConnector, IReportWriter
/adapters
  /storage-access     Access .accdb repository implementations
  /import-filedrop    Watched-folder / manual-upload — Phase 0, scan + kanban CSVs
  /import-live        [Phase 2] HTTP/SQL-view adapters, same interface as file-drop
  /report-excel       NWMS workbook writer (now literally reproducible sheet-by-sheet —
                       Register / Control Plan / FAIR / Flat Check / Formed Check / SPC Log / RFI Tracker,
                       confirmed against the real workbook)
  /report-pdf         Customer-facing PDF writer, incl. annotated drawing
  /drawing-render     PDF render + balloon overlay
/transport
  /http-server        HttpListener routing/auth/serialization only — no logic
/ui
  Vanilla JS/CSS, single stylesheet, tokens seeded from Tool Room Job Manager's
  --ink/--paper/--accent + spacing/radius scale (real values confirmed below)
```

**Tool Room's real design tokens** (pulled 2026-08-14 from `help.html` in `C:\Users\dave\Documents\Codex\Tool Room Job Manager` — same tokens the main app uses):

| Token | Light | Dark |
|---|---|---|
| `--ink` / `--ink-soft` | `#17181b` / `#3a3c40` | `#ece9e2` / `#c7c4bb` |
| `--paper` / `--surface` / `--surface-sunken` | `#f6f5f1` / `#ffffff` / `#eeece5` | `#17181a` / `#1f2023` / `#191a1c` |
| `--line` / `--line-strong` | `#e2dfd6` / `#cfccc1` | `#303236` / `#45474c` |
| `--muted` | `#6b6b6d` | `#8d8e91` |
| `--accent` / `--accent-soft` | `#3c5b74` / `#dfe6ea` | `#7fa5c2` / `#223038` |
| `--critical` / `--critical-soft` | `#a83c3c` / `#f3dfdc` | `#e08383` / `#331f1f` |
| `--green` / `--green-soft` | `#2f7a4d` / `#dfeee3` | (not seen in the sample pulled, check before use) |

Radius: `--radius-xs 3px`, `--radius-sm 6px`, `--radius-md 9px`, `--radius-xl 15px`, `--radius-chip 999px` (fully round). Spacing: `--space-1` through `--space-5` = `4/8/12/16/20px`. Fonts: `--font-sans: -apple-system, "Segoe UI", Roboto, Arial, sans-serif` (+ a `--font-mono` pair, not pulled yet). Dark-mode switch is `:root[data-theme="dark"]` / `[data-theme="light"]`, same pattern the artifact-design guidance elsewhere uses.

Not yet needed for a `--critical-attribute` or class-specific accent (Section 4.2's 6-value `Class` taxonomy) — Tool Room only has one non-neutral "critical" hue plus a green for pass/complete states, deliberately (a past design pass reduced an earlier five-plus-colour draft down to this). Worth deciding whether ISIR's richer `Class` taxonomy needs its own colour or should lean on weight/shape instead, same principle Tool Room already applied.

Domain has zero references to `System.Net`, Access/OleDb, or the DOM — verified by not importing them, not by convention alone (worth a lint/test rule once real code exists).

---

## 6. Phase 0 task breakdown

Revised slightly from the brief's own Section 7 given what the real register showed (Section 3.2's register-import suggestion folded in as 0.3):

1. **0.1 — Domain core.** Characteristic model, signed-limit tolerance evaluator (Section 4.1), unit handling, attribute-vs-variable type-level split. Unit tests written *from* the brief's Section 5 defect list as literal acceptance tests, using the real 52-balloon register as primary fixture (pending your Q1 answer).
2. **0.2 — Storage adapter.** Access `.accdb` repository for Part/DrawingRevision/Characteristic/Measurement, migrations pattern matching Planner/Tool Room's proven `SchemaMigrations` approach.
3. **0.3 — Characteristic ingest, spreadsheet path.** Import a characteristic register directly from CSV/XLSX (Section 3.2) — far less work than the drawing UI for proving the walking skeleton, and matches what your team already produces by hand.
4. **0.4 — Drawing balloon UI.** Render an uploaded PDF, place/edit balloons, link to Characteristics. Can follow 0.3 rather than block on it.
5. **0.5 — InspecVision scan importer.** UTF-16 tab-delimited parser (handle the BOM), both tolerance-string forms, independent recompute-and-cross-check against the scanner's own `Status` column, feature-to-balloon mapping UI with persistence.
6. **0.6 — Manual entry UI.** Operator/date/gauge/calibration-status captured at point of entry, not after.
7. **0.7 — Excel workbook generator.** Reproduce the real sheet set (Register/Control Plan/FAIR/Flat Check/Formed Check/SPC Log/RFI Tracker) — no longer a guess, I have the real column layout for all seven sheets.
8. **0.8 — Exit test.** Pending your answer on what "the corrected reference submission" actually is (Section 1) — can't finalise this test until I know whether it's a separate historical file or whether we're defining "done" against the real draft package instead.

---

## 7. Decisions needed before I start

The four biggest ones are in the chat message as a quick-answer set. Smaller open items, for whenever you get to them:

- Real InspecVision CSV export, real Kanban compliance CSV export, an annotated drawing PDF — all still needed, none found in Downloads.
- Is there a separate "corrected" historical ISIR workbook (the one with the real 50%-failure numbers), distinct from the draft `QCP-1394250-2-100` package I read? Needed to make the Phase 0 exit test concrete.
- What is `ISIR Report Builder — turn inspection workbooks into print-ready reports.pdf`? I couldn't open it in this environment — worth knowing before I plan around (or duplicate) whatever it describes.
- Is `drawing-compliance-dashboard-prompt.md` meant for this project, or a different one? (Section 3.4)
- Is full AIAG-VDA 7-step PFMEA genuinely new practice at NWMS, or does prior FMEA content exist somewhere I should see before scoping Phase 1's quick-text library? (Section 3.1)
- Gauge R&R / Attribute Agreement studies (QC Plan Section 6) — does the app need to hold this as evidence (pass/fail, %GRR, report attachment), or is it fully outside scope? (Section 1.2)
- What can the Planner and Kanban actually expose for Phase 2 — HTTP endpoint, read-only SQL view, or file-drop only? Brief already assumes file-drop for Phase 0 either way, so this doesn't block starting.

I'll hold off on Phase 0 work until at least the four chat-message questions are answered — the code-standard one especially changes how 0.1–0.2 get built, not just how fast.
