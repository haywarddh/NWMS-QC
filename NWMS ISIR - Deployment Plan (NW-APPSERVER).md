# NWMS Quality Records — deployment plan for NW-APPSERVER

*Written 2026-08-17. Mirrors the pattern already proven by the Weekly Delivery Planner
(`\\NW-APPSERVER\Master_Planner\`), so the two apps are operated the same way.*

---

## 1. What actually gets deployed

Two things, and only two:

| Part | What it is | Runtime needed on the server |
|---|---|---|
| **`qc-api.ps1`** + `scripts\` | The service: JSON API under `/api`, and the static file host | Windows PowerShell 5.1 — already there |
| **`dist\`** | The built front end (HTML/JS/CSS) | **None.** Plain files served by the above |

**Node.js is not installed on NW-APPSERVER and does not need to be.** The build happens
on your machine; the server only ever sees the output. This is the same shape as the
Planner — one PowerShell HTTP listener serving an app folder — with the difference that
the Planner's HTML is hand-written and this one is compiled first.

### The data folder is not part of the deployment

`data\` on the server holds live production content and **must never be overwritten by a
publish**:

```
data\plans\<id>.json     the quality records themselves
data\plans\index.json    the records list
data\attachments\*.jpg   photographic evidence (elcometer readings, packing…)
data\library.json        the shared route templates and station FMEA library
data\settings.json       the privileged-password hash
```

The publisher must treat this folder exactly as the Planner's publisher treats
`planner-data.accdb`: back it up, never copy over it. **`attachments\` is new and is the
one that would hurt most** — a lost photo cannot be retaken after the parts have shipped.

---

## 2. The build step (new — the Planner has no equivalent)

> **Status: FIXED AND PROVEN, 2026-08-17.** The stock build produced a **Cloudflare
> Workers bundle** with **no `index.html`** — nothing a static file host could serve.
> Two config changes fixed it, and the result has been served end-to-end through
> `qc-api.ps1` itself.

The app is entirely client-side — every byte of data arrives from `/api` at runtime —
so server-side rendering buys nothing. `vite.config.ts` now carries:

```ts
nitro: false,                    // no Cloudflare Worker; plain build into dist/
tanstackStart: {
  server: { entry: "server" },
  spa: { enabled: true, prerender: { outputPath: "/index.html" } },
},
```

Both were needed, and the reason is worth recording: with nitro left on, the build
writes to `.output/` while the SPA prerenderer looks for the server bundle in `dist/`,
so it fails with `Cannot find module dist/server/server.js`. Without `outputPath` the
shell is written as `_shell.html`, which the static host does not serve as a front page.

```bash
npm run build
```

**The deployable folder is `dist\client\`** — `index.html`, `assets\`, `favicon.ico`,
`robots.txt`. `dist\server\` is a by-product and is NOT deployed.

### Proven, not assumed

Served through the real service on a spare port
(`qc-api.ps1 -Port 8796 -WebRoot ...\dist\client`):

| Request | Result |
|---|---|
| `/api/health` | 200 JSON |
| `/` | 200 `text/html` |
| `/route`, `/report`, `/fmea` | 200 — the SPA fallback returns `index.html`, so a **hard refresh on a deep link works** |
| `/assets/styles-*.css` | 200 `text/css`, 93.6 KB |
| App in the browser | Boots, routes, no console errors |

**Confirm before every publish** that `dist\client\index.html` exists. If it does not,
the publish produces a site that 404s on its own front page.

### Fonts are self-hosted — no internet needed

**Done 2026-08-17.** The app previously pulled Barlow, Barlow Condensed and JetBrains
Mono from `fonts.googleapis.com`, which would have left every page — including a printed
ISIR a customer reads — silently falling back to system fonts on a LAN with no route out.

All three now ship with the app: 20 `.woff2` files in `public\fonts\` (~387 KB, Latin and
Latin-Extended subsets only), declared in `src\fonts.css`, imported by `styles.css`. All
three are SIL Open Font License 1.1, which permits self-hosting; the licence texts are
redistributed alongside them in `public\fonts\OFL.txt`.

`scripts\fetch-fonts.ps1` regenerates the files and the CSS — run that rather than
hand-editing `fonts.css` if a weight is ever added.

Verified on the built bundle served through `qc-api.ps1`:

- `/fonts/*.woff2` → 200 `font/woff2`
- All three families measurably render in their real typefaces, not fallbacks
  (Barlow Condensed 197px vs 240px for the serif fallback on the same string)
- **Zero external tags in the DOM and zero external network requests** — the app is
  fully self-contained and works with no internet at all

---

## 3. Ports

| Port | Use | Notes |
|---|---|---|
| 8080 | **Kelio** | Do not touch |
| 8765 | Planner (Live) | Existing |
| 8766 | Planner (Dev) | Existing |
| 8770 | Server Status Dashboard | Existing |
| **8791** | **Quality Records (Live)** | Proposed — matches the local dev port |
| **8792** | **Quality Records (Dev)** | Proposed |

Tester URL: `http://nw-appserver:8791/`

---

## 4. One-time administrator setup (first deployment only)

Run **on NW-APPSERVER**, signed in as an administrator, in an elevated PowerShell window.
This mirrors `Configure Network Planner.ps1` and needs a `Configure Quality Records.ps1`
writing to match (see §8).

1. **URL reservation** — binding the wildcard address needs either Administrator rights
   at every start, or a one-time reservation for the account that will run it:
   ```powershell
   netsh http add urlacl url=http://+:8791/ user=DOMAIN\ServiceAccount
   ```
   Without this you get `Access is denied` from `$listener.Start()`; with it, the service
   starts unelevated forever after.

2. **Firewall rule, Domain profile:**
   ```powershell
   New-NetFirewallRule -DisplayName "NWMS Quality Records - TCP 8791" `
     -Direction Inbound -Protocol TCP -LocalPort 8791 -Action Allow -Profile Domain
   ```
   **The known trap:** the Planner guide records this precisely — if the active network
   is classified *Private* or *Public* rather than *Domain*, this rule silently never
   matches and connections are **dropped, not refused**, which looks exactly like a
   timeout rather than a firewall problem. Check with `Get-NetConnectionProfile` first.

3. **Create the folders** and copy the release in by hand this once
   (`\\NW-APPSERVER\Quality_Records\`), including an empty `data\`.

4. **Change the privileged password.** It ships as `nwms-quality` and the service prints
   a warning saying so at every start until it is changed. Generate a hash and drop it
   into `data\settings.json` — the recipe is in `qc-api\README.md`.

5. **Start it** and confirm:
   ```powershell
   Invoke-RestMethod http://localhost:8791/api/health
   ```
   then the same from another PC via `http://nw-appserver:8791/api/health`.

---

## 5. Publishing an update (the normal loop)

Same discipline as the Planner, and the same rule that has kept it safe: **nothing on
NW-APPSERVER is ever driven remotely.** You start and stop the service there yourself.

1. **Build and test locally.** `npm run build`, confirm `index.html` exists, and check
   the app works against the local service on 8791.
2. **Update `CHANGELOG.md` and the version** in `qc-api.ps1` — the Planner and Tool Room
   both live or die by this; a deployed build whose version you cannot identify is the
   thing that wastes an afternoon later.
3. **Stop the service on NW-APPSERVER** (close its window, or find it by command line —
   see the PID-4 note in §7).
4. **Run the publisher from your LOCAL folder.** It backs up `data\` and the previous
   code into `Releases\`, then copies `qc-api.ps1`, `scripts\` and `dist\` — and nothing
   else.
5. **Start the service on NW-APPSERVER.**
6. **Verify**: `/api/health` returns the version you just published; open the app and
   confirm the Records list and the shared library are intact.

### Dev before Live

Both Tool Room and the Planner run a Dev instance alongside Live, and the standing rule
is that **nothing goes to Live until UAT is confirmed on Dev**. Same here: publish to
8792, confirm, then publish to 8791. Dev must point at its **own** `data\` folder — a Dev
instance sharing Live's records would let a test edit a controlled record.

---

## 6. Rollback

`Releases\` holds the previous code and `Backups\` holds timestamped copies of `data\`.
To roll back: stop the service, restore the previous release folder over the app files,
restore the matching `data\` backup **only if the data itself is the problem**, and start
again. Restoring old code against current data is usually right; restoring old data over
newer records is almost always wrong — it destroys work done since.

---

## 7. Things that will bite, written down now

**Finding the process.** `netstat` / `Get-NetTCPConnection` report the listening socket as
owned by **PID 4 (System)** because of http.sys — useless for finding the service. Use:
```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*qc-api.ps1*' }
```
And if it was started elevated, you need an elevated session to see or stop it.

**Single-threaded service.** One request at a time, exactly like `sage-bridge.ps1`. Two
consequences specific to this app: a **15MB photo upload blocks every other user** for its
duration (the browser downscales to ~200KB first, which is why that matters), and a large
plan PUT does the same. Acceptable for the expected handful of users; worth remembering
when someone reports "it froze for a moment".

**Deleting records while someone has them open.** Learned the hard way during testing: a
browser holding a plan **re-saves it within seconds** of deletion. Close the plan (or the
tab) first, then delete. Same for tidying up test data.

**No authentication.** Anyone who can reach the port can read and write everything except
the privileged actions. That is why the firewall rule is Domain-scoped and why this must
not be exposed beyond the LAN.

**Browser caching of the app shell.** `index.html` must not be cached hard or users will
run an old build after a publish. Attachment images are deliberately cached forever
(their ids are unique and their content never changes), which is safe and is not the same
thing.

---

## 8. What still needs writing before the first deployment

These do not exist yet — the Planner's equivalents are the template for each:

- [x] ~~**`vite.config.ts` SPA change** and a verified build producing `index.html`~~ — done
      and proven end-to-end through `qc-api.ps1` (§2)
- [ ] **`Configure Quality Records.ps1`** — urlacl + firewall + machine-name guard
- [ ] **`Publish Quality Records.ps1`** — validate, back up `data\` (including
      `attachments\`), copy app files only, refuse to run from the network folder
- [ ] **`Deploy to NW-APPSERVER.cmd`** — the one-double-click local wrapper
- [ ] **`Start Quality Records Server.cmd`** — starts with `-ListenAddress "+"` and the
      right `-WebRoot`/`-DataDir`
- [ ] **`Rollback Quality Records.ps1`**
- [ ] **A service lock** equivalent to `planner-service.lock`, so a publish cannot land
      while the service is running
- [ ] **A scheduled backup** of `data\` — the Planner backs up its Access file; this app
      now has records, photos and the shared library to lose

---

## 9. The five open questions, answered

Answered 2026-08-17 from evidence off the server itself, not from assumption. Probing
was read-only: TCP connects to see which ports answer, and SMB reads of the existing
shares. Nothing was executed on NW-APPSERVER.

### 1. Share name → `\\NW-APPSERVER\NWMS_QC\` and `\\NW-APPSERVER\NWMS_QC_Dev\`

**Already created — Dave made them.** An earlier draft of this section proposed
`Quality_Records` on the basis that it "did not exist"; that was wrong, and wrong in an
instructive way: it tested only the name that had been guessed instead of enumerating
what is actually there. The full share list on NW-APPSERVER is:

```
Cim50               Cim502              SAGE2020         SageBackups
Master_Planner      Master_Planner_Dev
Tool_Room           Tool_Room_Dev
NWMS_QC             NWMS_QC_Dev        <- ours, already made, both EMPTY and WRITABLE
server_status       Payroll            SQL_Move
```

Two things this settles beyond the name:

- **Dev is its own share, not a subfolder.** Every app here follows
  `<App>` + `<App>_Dev` as two separate shares with two separate trees. So Quality
  Records gets `NWMS_QC` for Live and `NWMS_QC_Dev` for Dev, each with its own
  `data\`, which is exactly the isolation the service lock enforces anyway.
- **Both shares are empty and writable from this laptop** (probed by creating and
  deleting a temp file), so the first publish can bootstrap them without any manual
  copying — unlike the Planner, whose publisher refuses to create its Access database
  and therefore needed a hand-built first deployment.

The other apps' trees confirm the shape to aim for — `assets\`, `scripts\`,
`Backups\`, `Releases\`, `CHANGELOG.txt`, the launchers in the root, and `index.html`
at top level for Tool Room. Ours differs in one deliberate way: the front end is a
**built** bundle, so it lives in `web\` rather than loose HTML in the root.

### 2. Ports 8791 / 8792 → both free. Confirmed.

Probed from this machine:

| Port | What answers | Verdict |
|---|---|---|
| 8765 | Planner **LIVE** | in use |
| 8766 | Planner **Dev** | in use |
| 8768 | **Tool Room** | in use |
| 8770 | Server Status — deployed but never started | reserved in practice, leave it |
| **8791** | nothing | **free — take it for QC LIVE** |
| **8792** | nothing | **free — take it for QC Dev** |

So the proposal stands unchanged, and it has the pleasant property of matching the port
already used locally, so there is one number to remember rather than two.

### 3. Service account → a **local NW-APPSERVER account**, and you must supply its name

This is the one where the evidence is partial, and the partial answer is itself useful.
The live Planner's files and its Access database are owned by:

```
S-1-5-21-2073381167-3160167326-2882534365-1001
```

That is **not** your laptop account (`DAVE_PROART\dave`, a different SID entirely), and
it cannot be resolved to a name from here — which is expected and correct, because this
laptop is deliberately non-domain. The `-1001` ending marks it as the first ordinary
account created on that machine, i.e. a **local** account on NW-APPSERVER.

What that means concretely for the urlacl line:

```powershell
# NOT DOMAIN\ServiceAccount -- there is no domain in play here
netsh http add urlacl url=http://+:8791/ user=NW-APPSERVER\<that account>
```

`Configure Quality Records.ps1` defaults `-RuntimeAccount` to
`"$env:USERDOMAIN\$env:USERNAME"`, which resolves correctly **when you run it while
signed in as that same account on the server** — which is how the Planner's was done.
So: sign in as the account that already runs the Planner, and the default is right.
**Please confirm the account name when you are next on the server**, and note it here —
it is the one detail no amount of probing from this side can produce.

### 4. Dev instance → **yes, set it up, but Live first**

Both other apps run a Dev instance beside Live (8766 and, for Tool Room, its own), and
the standing rule on this estate is that nothing reaches Live before UAT on Dev. But
there is nothing to UAT *against* yet — so the pragmatic order is:

1. Stand up **LIVE on 8791** and get one real part through it end to end.
2. Add **Dev on 8792** before the second round of changes, at which point it starts
   earning its keep.

Non-negotiable when you do: Dev needs its **own `-DataDir`**. A Dev instance sharing
Live's `data\` would let a test edit a controlled record — and the service now refuses
to start twice against one data folder, so it will stop you rather than let it happen.

### 5. First real user → arguably already decided

The honest framing: with no authentication, "deployed" and "in use" are the same moment,
so this is really the question *whose work is on it first*.

You have already answered it in practice. The live service currently holds one real
record — **`1394250-2-100-02- Transfer Rail 2920 Long`**, a draft with one PMP and the
drawing embedded — created on this machine on 2026-08-17. That part going through the
deployed instance is the natural first job, and it has the advantage that you are the
one holding it, so the first user is also the person who can tell what "wrong" looks
like.

Two things worth deciding before anyone else touches it:

- **Change the privileged password** from the default `nwms-quality`. The service warns
  about it at every start until you do.
- Decide **who else gets told the URL**, because that is the whole access-control model.
  The firewall rule is Domain-profile and LAN-only by design; there is nothing else
  stopping a person who knows the address.
