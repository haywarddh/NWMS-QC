# Workflow & gap analysis — app vs the real 1394250-3-105 ISIR

*Written 2026-08-16, against `N:\1 nw metal sections\Customer Documents\Whittan\Drawings\1394250-3-105-01\1394250-3-105 ISIR.xlsx` (last saved 10/08/2026). Companion to "NWMS ISIR - Plan & Data Model.md".*

---

## 1. What the reference workbook actually contains

| Tab | Content |
|---|---|
| **Process Flow** | 17 numbered steps, order received → MRP/Kanban → material purchase/receipt/storage → CG1540 combo tower → punch/laser → **InspecVision scan of flat pattern** → fold → **InspecVision scan of formed geometry** → packing → dispatch. Each step has a one-line description. |
| **PMP** (control plan) | 10 rows. Per row: step no, process (Laser Cutting / Press Brake), machine ("CG1540 Prima Power", "Bystronic Xact 4m"), **Char No = drawing balloon** ("3B", "6B", "6B x 2 features", "6B (x 4 locations)", "n/a" for visual checks), **process parameters** (multi-line: tooling selection, tonnage, bend sequence, backgauge, crowning…), parameter description w/ nominal+tolerance ("Top Flange Length - 68.5mm +0mm / -1mm"), critical marking, **measurement method incl. gauge serial** ("Mitutoyo Digital Angle Vernier: GG24430439", "InspecVision Planar P220…36", "Calibrated Radius Blades", "visual"), sample size, **compound frequency** ("Shift Start, Material Batch Change, 2XH"), **analysis method** ("SPC - Kanban" / SPC + control charts + Cp/Cpk + trend review), **reaction if out of control** (multi-line: stop production, adjust crowning/tonnage, re-align backgauge, re-check program, re-inspect last conforming batch), control location ("C / D"). Header: **three-role NWMS approvals** (Engineering / Production / QA, init + date) + the control-location and frequency legends. |
| **FMEA** | Full **AIAG-VDA 7-step PFMEA**, 17 rows covering the whole route — GI-01..03 (goods-in/material verification), CG1540-01..05 (laser, punch, batch check, program load, cut quality), PB-01..03 (tool setup, form geometry, surface protection), PK-01..03 (segregate, quantities, protection), LB-01..03 (label data, print quality, application). Columns: Structure analysis (process item / process step / **4M work element**) → Function analysis (3 columns) → Failure analysis (FE, **S**, FM, FC) → Risk analysis (**prevention control** and **detection control separately**, **O**, **D**, **AP rating H/M/L** — not RPN, **special characteristic class**, filter code) → **Optimisation** (prevention action, detection action, **responsible person, target date, status Open/…, action taken w/ evidence pointer, completion date, and post-action re-scored S/O/D/AP**). |
| **PMP - 1-8** (results) | Three sample runs × PMP1–8, **one row per instance** (PMP6 ×2 lips, PMP7 ×4 angles, PMP8 ×4 radii). Columns: Name, **Instance**, Entity, **Datum** ("edge", "web", "top flange"), **Type** (horizontal/vertical), Nominal, Tol-lower, Tol-upper, Measured, Result, Deviation, **Chkd (initials KW)**, Date, **Reason ("Samples ISIR")**. PMP8 (bend radius 4mm +1/−0, measured 3mm) is a genuine **reject ×12 across all three samples**. Float-noise deviations (−3.0000000000001137E-2) are the exact Excel artifact the kickoff brief complained about. |
| **PMP 9-10** (attribute checks) | PMP9 = section complies with drawing notes (debris, twist, burrs, parallelism); PMP10 = **check for cracking around bend radius ×8 instances, with a reference image** ("see image for example of cracking that must be avoided"). Plus the **drawing's GENERAL NOTES transcribed as requirements** (material 3mm pre-galv S350 GD BS EN 10346, default radii 4mm, angles 90°, general tol ±1.0mm/±1.0°, tooling marks minimised, no burrs, finish natural, weight 0.8kg). |

## 2. The workflow question — "drawing → PMP → FMEA"

The workbook itself follows the classic APQP core-tool spine, and it's worth adopting because each document *feeds* the next:

```
1. PROCESS FLOW        which steps does this part travel through?
        │                (mostly inherited — every Whittan rail is
        ▼                 goods-in → punch/laser → scan → fold → scan → pack)
2. PFMEA               what can go wrong AT EACH STEP?
        │                (process-level, library-driven, mostly reused;
        ▼                 special characteristics fall out of it)
3. CONTROL PLAN (PMP)  how do we control each step?
        │                drawing ballooning happens HERE — each balloon
        ▼                becomes a controlled characteristic ON a step
4. COLLECT EVIDENCE    per-instance results, scans, attribute checks
        ▼
5. REVIEW → APPROVE    NWMS 3-role sign-off, then customer
```

Key insight from the reference: **the FMEA is about the process, not the part**. Its 17 rows (GI-01…LB-03) apply verbatim to every part made on that route — only the special-characteristic links and the odd part-specific row change. The app currently hangs one FMEA off each PMP, which is the wrong grain: it forces re-answering process questions per dimension and can't represent goods-in/labelling/dispatch risks at all (they have no balloon).

**Proposed app workflow** (keeps the drawing workbench as the star):

1. **New ISIR** — part details + drawing upload (as now).
2. **Process route** *(new, small)* — pick/confirm the process flow from a route template; steps carry their machines. Inherited, editable, rarely touched.
3. **FMEA** — rows attach to *route steps*, seeded from the library by process type (library mechanics already exist). Part-specific rows added where needed.
4. **Drawing & control plan** — balloon PMPs on the drawing (as now), but **every PMP must be assigned to a route step** (this is kickoff-brief rule 2, currently unenforceable because `Pmp` has no step field), and the control-plan detail lives here (gauge, frequency, reaction plan, analysis method).
5. **Evidence → Review → Approval** as now, plus per-instance results.

## 3. Gaps — PMP / control plan

Grounded column-by-column against the PMP tab. `Pmp` in `plan-store.tsx` currently holds: ref, description, critical, checkType, nominal, tolUpper/tolLower, unit, verification (4-way enum), verificationDetail, interval, controlLocation, sampleSize, x/y/page, placed, fmea{…}.

| Reference detail | In app today? | Note |
|---|---|---|
| Process step + machine per characteristic | **No** | Biggest gap; blocks rule 2 ("every balloon maps to a process step") |
| Occurrences / instances ("6B x 2 features", "(x 4 locations)") | **No** | One value slot per PMP; results need per-instance rows |
| Process parameters (tooling, tonnage, backgauge, crowning…) | **No** | Belongs to the step, not the PMP |
| Reaction if out of control (multi-line plan) | **No** | Core control-plan column |
| Analysis method (SPC - Kanban / control charts / Cp/Cpk) | **No** | Capability page computes Cpk but the plan never declares the method |
| Gauge with serial ("Mitutoyo … GG24430439") | Partial | Free-text `verificationDetail`; no gauge register / calibration status (brief lists an uncalibrated gauge as an audit embarrassment) |
| Compound frequency ("Shift Start, Material Batch Change, 2XH") | Partial | Single `interval` code; real plans combine several triggers |
| Multiple control locations ("C / D") | Partial | Single code string |
| 3-role NWMS approvals (Eng / Production / QA, init + date) | **No** | App has only the customer-approval step |
| Drawing general notes as checkable requirements (PMP9 pattern) | **No** | Material spec, default tolerances, finish, weight — nothing captures them |
| Datum + measurement type (edge/web; horizontal/vertical) | **No** | Lives on the results sheets; also useful for scanner-feature matching |

## 4. Gaps — FMEA

The app's per-PMP `fmea{failureMode, effect, cause, control, sev, occ, det}` + RPN vs the reference AIAG-VDA columns:

| Reference detail | In app today? | Note |
|---|---|---|
| FMEA rows at process-step level (GI/CG1540/PB/PK/LB) | **No** | App is per-PMP; goods-in/labelling/dispatch risks are unrepresentable |
| Structure analysis: process item / step / 4M work element | Library only | `FmeaTemplate` carries process/area/workElement, but the per-PMP `fmea{}` **drops them on apply** |
| Function analysis (3 columns) | **No** | |
| Prevention vs detection control, separated | Library only | Per-PMP `fmea{}` has a single `control`; `detectionControl` is lost on apply |
| AP (Action Priority H/M/L) | **No** | App computes RPN + custom Run Score; the real doc is AIAG-VDA AP |
| Special characteristics class per row | Library only | Dropped on apply |
| **Optimisation block**: prevention action, detection action, responsible, target date, status, action-taken w/ evidence, completion date | **No** | This is kickoff-brief rule 6's home ("predicted is not achieved") and feeds review ("FMEA action still open with no completion date") — currently nowhere to record it |
| Post-action re-scored S/O/D/AP | **No** | The workbook keeps both current and predicted scores side by side |

*(Also present in the real FMEA rows: dates stored as Excel serials — e.g. target date `45717` — the kind of artifact the app should normalise on import, same as the float noise.)*

## 5. Gaps — results / evidence

| Reference detail | In app today? | Note |
|---|---|---|
| Per-instance rows (PMP7 ×4 bend angles each sample) | **No** | CSV rows can carry repeats, but nothing models instance identity |
| Sample-run grouping (3 ISIR sample parts) | **No** | "Reason: Samples ISIR" groups a full set per physical sample |
| Checked-by initials + date per reading | **No** | Manual checks have no who/when |
| Deviation shown per reading | Derivable | Compute, never store — avoids the float-noise artifact |
| Attribute check vs reference image ×N instances (PMP10) | Partial | `ManualCheck` has illustration + result, but single-instance |

## 6. What the app already does right (keep)

- Drawing-first ballooning with normalised x/y/page — the workbook has no equivalent; this is the app's edge.
- Asymmetric tolerances handled natively (`+0/−1` on flanges and radius are live examples here).
- Blank ≠ fail (`evaluate()` returns "unknown") — the old phantom-failure defect stays fixed.
- Interval + control-location libraries already match this workbook's legends verbatim.
- FMEA seed library with process/area/4M/detection/special fields — the *template* shape is close to AIAG-VDA already; it's the per-PMP application that flattens it.
- Readiness gating, Cpk/Gauge R&R, customer approval flow, shared server storage.

## 7. Proposed data-model changes (sketch)

```ts
/** New: the route the part travels — inherited from a template. */
interface RouteStep {
  id: string;
  seq: number;
  code: string;            // "CG1540-01", "PB-02" — matches FMEA station codes
  process: string;         // "Laser Cutting", "Press Brake", "Packing"
  machine?: string;        // "Bystronic Xact 4m"
  description: string;
  processParameters: string[];   // tooling selection, tonnage, backgauge…
  scanPoint?: boolean;     // InspecVision checkpoints in the flow
}

interface Pmp {
  // existing fields, plus:
  stepId: string;          // REQUIRED — enforces rule 2
  instances: number;       // "x 4 locations" — results expect one reading per instance
  datum?: string;          // "web", "top edge"
  measureType?: string;    // "horizontal" | "vertical" | …
  gauge?: { name: string; serial?: string };  // future: link to gauge register
  frequencyTriggers: string[];   // ["SS", "MC", "2X/H"] — compound frequency
  reactionPlan: string;    // "Reaction if out of control"
  analysisMethod?: string; // "SPC - Kanban", "Cp/Cpk"…
}

/** FMEA row moves to the step (library-instantiated), AIAG-VDA shaped. */
interface FmeaRow {
  stepId: string;
  // structure/function/failure analysis columns as in FmeaTemplate…
  preventionControl: string;
  detectionControl: string;
  sev: number; occ: number; det: number;
  ap: "H" | "M" | "L";           // derived per AIAG-VDA table
  specialCharacteristic?: string;
  pmpIds: string[];              // links to affected characteristics
  actions: FmeaAction[];         // the optimisation block
}

interface FmeaAction {
  kind: "prevention" | "detection";
  text: string;
  responsible: string;
  targetDate?: string;
  status: "open" | "in-progress" | "done";
  evidence?: string;
  completedAt?: string;
  predicted: { sev: number; occ: number; det: number };  // rule 6: shown as prediction until done
}

interface Reading {                 // per-instance evidence
  pmpId: string;
  instance: number;                 // 1-based
  sampleRun?: string;               // "ISIR sample 1"
  value: string;
  checkedBy?: string;
  checkedAt?: string;
  source: "csv" | "manual" | "scan";
}
```

## 8. Suggested build order

1. **Route steps + PMP↔step assignment** — unlocks rule 2, the workbench grouping, and gives FMEA its anchor. Smallest change with the biggest structural payoff.
2. **Control-plan detail on the PMP** — reaction plan, compound frequency, analysis method, gauge name/serial, instances.
3. **FMEA re-grain to step level** + keep the AIAG-VDA fields the library already has (stop flattening on apply); add the actions/optimisation block with open-action surfacing in Review.
4. **Per-instance results** + checked-by/date + sample-run grouping.
5. **NWMS 3-role approvals** ahead of customer approval; drawing general-notes checklist.

## 9. Decisions needed from Dave

1. **FMEA grain**: move to process-step level with PMP links (as the real doc), or keep per-PMP and *add* the missing columns? (Recommendation: step level — it's what your own document does, and it makes the library genuinely reusable.)
2. **Risk rating**: adopt AIAG-VDA **AP (H/M/L)**, keep **RPN**, or show both? (The workbook is pure AP; the app's Run Score is a home-grown blend.)
3. **Action tracking scope**: full optimisation block now (responsible/target/status/evidence/re-score), or a lighter "open actions" list first with the full block later?
4. **Route templates**: one standard NWMS route seeded from this workbook's 17 steps, tweaked per part — or built per part from scratch each time?
5. **Gauge register**: worth a small first-class register now (name, serial, calibration due date) so Review can flag out-of-cal gauges, or keep gauge as free text until the register exists elsewhere?
