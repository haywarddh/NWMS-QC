# qc-api

Small PowerShell HTTP service that backs the NWMS ISIR / QC planning front-end
(the sibling `qc` repo). It stores quality plan records and the FMEA template
library as JSON files on disk, replacing the browser-localStorage mock in
`qc/src/lib/plan-repository.ts` so plans are shared across machines instead of
being trapped in one browser profile. It also serves the built front-end, so in
production one process is the whole app.

Same architecture as the other NWMS PowerShell bridges: `System.Net.HttpListener`
with a single-threaded request loop. Windows PowerShell 5.1 compatible.

## Starting it

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\qc-api.ps1
```

| Parameter         | Default                          | Meaning                                        |
| ----------------- | -------------------------------- | ---------------------------------------------- |
| `-Port`           | `8791`                           | Port to listen on (`http://localhost:8791/`)   |
| `-WebRoot`        | `..\qc\dist` (relative to script)| Folder with the built front-end                |
| `-DataDir`        | `.\data` (relative to script)    | Where plan/library JSON is stored              |
| `-ListenAddress`  | `localhost`                      | Interface to bind. `+` = every interface (LAN) |
| `-InstanceLabel`  | *(blank)*                        | `LIVE` / `DEV`; shown in the banner and health |

Defaults resolve relative to the script's own folder, not the current
directory, so it behaves the same however it is launched. Stop with `Ctrl+C`.

`-ListenAddress localhost` binds with no privileges at all and is reachable
only from the machine running it — the right default, so an accidental bare
invocation never puts an unauthenticated app on the network. See **LAN /
NW-APPSERVER** below before changing it.

`-InstanceLabel` is cosmetic but matters in practice: a LIVE and a DEV instance
are otherwise two identical black console windows, which is how someone stops —
or publishes over — the wrong one.

Only **one** service may use a given `-DataDir`: an exclusive lock is held on
`<DataDir>\qc-api.lock` for the life of the process, because two services
sharing a data folder would interleave writes to `plans\index.json` and lose
records. A second instance on the same folder refuses to start and says so. To
run a Dev instance alongside Live, give it its own `-DataDir` **and** `-Port`.

During development the Vite dev server proxies `/api` to
`http://localhost:8791`, so run `qc-api.ps1` alongside `npm run dev` and the
front-end talks to it same-origin.

## Endpoints

| Method   | Path              | Response                                                        |
| -------- | ----------------- | --------------------------------------------------------------- |
| `GET`    | `/api/health`     | `{"ok":true,"service":"qc-api","version":"0.4.0","instance":"LIVE","plans":N}` |
| `GET`    | `/api/plans`      | `PlanMeta[]`, newest `updatedAt` first                          |
| `GET`    | `/api/plans/all`  | `PlanRecord[]` (full records; dashboard roll-up)                |
| `GET`    | `/api/plans/{id}` | `PlanRecord`, or `404 {"error":"not found"}`                    |
| `PUT`    | `/api/plans/{id}` | Body: full `PlanRecord` JSON. Returns `{"ok":true}`             |
| `DELETE` | `/api/plans/{id}` | `{"ok":true}` — idempotent, 200 even if the plan never existed  |
| `GET`    | `/api/library`    | `{"templates":FmeaTemplate[],"removedSeeds":string[]}`          |
| `PUT`    | `/api/library`    | Body: same shape. Returns `{"ok":true}`                         |
| `GET`    | `/api/privileged` | `{"configured":true\|false}` — is a password set?               |
| `POST`   | `/api/privileged/verify` | Body: `{"password":"..."}`. Returns `{"ok":true\|false}` |
| `POST`   | `/api/attachments` | Body: raw image bytes. Returns `201 {"id":...,"contentType":...,"bytes":N}` |
| `GET`    | `/api/attachments/{id}` | The image bytes, or `404 {"error":"not found"}`           |
| `DELETE` | `/api/attachments/{id}` | `{"ok":true}` — idempotent                                |

All responses are JSON (UTF-8, `application/json`) with one exception —
`GET /api/attachments/{id}` returns raw image bytes. Errors are always
`{"error":"message"}` with a 4xx/5xx status. The record shapes are defined by
the TypeScript source of truth in `qc/src/lib/plan-repository.ts` and
`qc/src/lib/plan-store.tsx`.

Any non-`/api` GET serves the built front-end from `-WebRoot`, with an
`index.html` fallback for extensionless paths so client-side routes survive a
page refresh.

## Data layout

```
data\
  plans\
    index.json     PlanMeta[] — the list/summary index, newest updatedAt first
    <id>.json      one full PlanRecord per plan, id = crypto.randomUUID()
  attachments\
    <id>.jpg       one uploaded photo per file; id = 32 hex chars, server-generated.
    <id>.png       The extension IS the stored content type — no sidecar metadata.
    <id>.webp
  library.json     {"templates":[...],"removedSeeds":[...]}
  settings.json    {"privilegedPasswordHash":"<hex sha256>","updatedAt":"..."}
```

Two deliberate storage rules, worth knowing before touching the code:

- **Plan bodies are stored byte-for-byte as the browser sent them.** They are
  never round-tripped through `ConvertFrom-Json`/`ConvertTo-Json` — PowerShell
  5.1 mangles deep or large JSON, and plan records carry multi-megabyte drawing
  data URLs. The only thing ever parsed out of an incoming record is
  `record.meta`, to keep `index.json` current. `GET /api/plans/all` builds its
  response by string-concatenating the raw files.
- **All writes are atomic-ish and BOM-free.** Content goes to `<file>.tmp`
  first, then is moved over the target, so a crash mid-write cannot leave a
  half-written file. Everything is UTF-8 *without* a byte-order mark — a BOM
  would break `JSON.parse` in the browser.

Backing up the whole system = copying the `data` folder.

## Privileged actions

The app has no user accounts — that is deliberately out of scope. Instead, a
few destructive / sign-off actions are gated by **one shared password**, and the
check happens **here in the service, not in the browser**, so the secret is not
sitting in the front-end bundle for anyone to read with View Source.

- `GET /api/privileged` answers only *"is a password set at all?"*
  (`{"configured":true}` / `{"configured":false}`). It never returns the
  password or its hash.
- `POST /api/privileged/verify` takes `{"password":"..."}` and answers
  `200 {"ok":true}` or `200 {"ok":false}`. A wrong password is **not** a `401` —
  it is an expected answer, not a transport error. Only a malformed request
  (not JSON, no `password` field) gets a `4xx`.

The front-end never stores the password. It sends it once per unlock, keeps
only a boolean "unlocked" flag in React state, and re-asks after a page reload.

**Storage.** `data\settings.json` holds a SHA-256 hex hash, never the
plaintext. The incoming password is trimmed of trailing CR/LF only (a stray
newline from a form or scanner) — leading and inner spaces are real characters
and are preserved. Hashes are compared as full 64-character hex strings,
case-insensitively.

**First run** seeds the file from the default password `nwms-quality` and
prints a warning under the startup banner. **Change it.**

```powershell
# 1. Hash the new password (paste your own in place of NEW-PASSWORD-HERE)
$hasher = [System.Security.Cryptography.SHA256]::Create()
$hash = -join ($hasher.ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes('NEW-PASSWORD-HERE')) |
    ForEach-Object { $_.ToString('x2') })
$hasher.Dispose()

# 2. Write it (adjust the path if you use a custom -DataDir)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd\THH:mm:ss.fff\Z')
$json = '{"privilegedPasswordHash":"' + $hash + '","updatedAt":"' + $stamp + '"}'
[System.IO.File]::WriteAllText(
    '.\data\settings.json', $json, (New-Object System.Text.UTF8Encoding($false)))

# 3. Restart the service.
```

A `settings.json` that fails to parse is **not** repaired or overwritten — a
hand-edit typo leaves privileged actions locked (`{"configured":false}`, every
verify returns `ok:false`) rather than silently resetting the password back to
the default. Fix the file, or delete it to be re-seeded with the default.

## Attachments (photo evidence)

ISIRs need photographs — elcometer readings, packing, labelling, reference
shots of a defect. Those images are stored as **separate files**, and a plan
record holds only their ids.

**Why not just put a data URL on the plan?** Because the plan body is
re-uploaded on *every* 700 ms autosave, and the front-end also mirrors it into
browser localStorage, which caps out around 5–10 MB. Either one falls over
after a couple of phone photos. Uploading an image once and referencing it by
id keeps plan records small and text-shaped.

| Method   | Path                    | Notes                                                     |
| -------- | ----------------------- | --------------------------------------------------------- |
| `POST`   | `/api/attachments`      | The body **is** the image — raw bytes, no JSON envelope, no multipart. The `Content-Type` header states the type. Returns `201 {"id":"<32 hex>","contentType":"image/jpeg","bytes":N}` |
| `GET`    | `/api/attachments/{id}` | The image bytes with the stored `Content-Type`, or `404 {"error":"not found"}` |
| `DELETE` | `/api/attachments/{id}` | `{"ok":true}` — idempotent, 200 even if it never existed   |

```powershell
# Upload, then read it back (PowerShell)
$png  = [System.IO.File]::ReadAllBytes('C:\photos\elcometer.png')
$resp = Invoke-WebRequest -Uri http://localhost:8791/api/attachments `
        -Method Post -Body $png -ContentType 'image/png' -UseBasicParsing
$id = (ConvertFrom-Json $resp.Content).id
# -> http://localhost:8791/api/attachments/$id  is now a plain <img> src
```

**Accepted types: `image/jpeg`, `image/png`, `image/webp` — nothing else.**
Any other content type is rejected with `415`. This is an evidence store for
the QC app, not general file hosting; keeping the list to three types means
nothing executable or scriptable can be parked in the data folder.

**Size cap: 15 MB per attachment** (`413` over it, and the cap is applied
*while* the body is read, not after). The browser downscales photos before
uploading, so a real ISIR photo lands well under a megabyte — 15 MB is
headroom for an un-downscaled phone original.

**Ids are generated by the service**, never supplied by the client: 32 hex
characters from `RandomNumberGenerator`. On read and delete the id must match
`^[a-f0-9]{32}$` exactly (`400` otherwise) — that is the path-traversal guard
for `data\attachments\<id>.<ext>`. The **file extension is the type record**,
so there is no sidecar metadata file that could drift out of step: a `GET`
tries `jpg`/`png`/`webp` and maps whichever exists back to a `Content-Type`.

**Caching.** Reads send `Cache-Control: public, max-age=31536000, immutable`.
That is safe precisely because ids are unique and content never changes under
one — an edited photo is a *new* upload with a *new* id.

### Deleting a plan does NOT delete its attachments

This is a deliberate decision, not an oversight. An amended revision can
reference the **same photo ids** as the plan it was copied from, so cascading
a delete would destroy evidence that is still in use by another plan. Orphaned
image files are cheap (a few MB of disk); destroyed quality evidence is not.

Attachments are therefore only removed by an explicit
`DELETE /api/attachments/{id}` — i.e. when someone removes a photo from a plan
on purpose. If orphans ever need sweeping up, that wants a deliberate
reference-counting pass across every plan record, not a delete hook.

## Serving the built front-end (NW-APPSERVER later)

1. In the `qc` repo: `npm run build` → produces `qc\dist`.
2. Copy both folders to the server keeping them side by side:
   ```
   <somewhere>\qc\dist\...        (built front-end)
   <somewhere>\qc-api\qc-api.ps1  (this service + its data folder)
   ```
   or pass `-WebRoot` pointing wherever `dist` lives.
3. Start `qc-api.ps1`. One process now serves the app and its API from a single
   origin, so there is no CORS to configure.

### LAN / NW-APPSERVER

To be reachable from other machines, start it with `-ListenAddress "+"` (every
interface). Two things gate that, and both fail in ways that look like something
else:

1. **The bind is privileged.** `+` needs either an elevated PowerShell window
   every time, or — better — a one-time URL reservation for the account that
   runs the service, after which it starts unelevated forever:

   ```powershell
   netsh http add urlacl url=http://+:8791/ user=DOMAIN\ServiceAccount
   ```

   Without it, `$listener.Start()` fails with a bare `Access is denied`, which
   reads like a file or share permission problem and is not one. The service
   catches that specific case and prints both fixes in plain English rather than
   a .NET stack. A reservation covers one *exact* URL, so a Dev instance on
   another port needs its own line.

2. **The firewall rule must match the network profile.** Allow the port inbound
   on the **Domain** profile. The trap, recorded on the Planner: if the active
   network is classified *Private* or *Public* instead of Domain, a
   Domain-profile rule silently never matches and connections are **dropped, not
   refused** — indistinguishable from a timeout. Check with
   `Get-NetConnectionProfile` before suspecting anything else.

Because the app has **no user authentication** (see limitations below), that
rule is what keeps it LAN-only, and it must stay that way.

**Finding the running service.** Not by port: `netstat` and
`Get-NetTCPConnection` report the listening socket as owned by **PID 4
("System")** because of http.sys. Use the command line instead:

```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*qc-api.ps1*' }
```

If it was started elevated, you need an elevated session to see it or stop it.

## Known POC limitations

- **Single-threaded.** One request at a time; a slow request (huge plan PUT)
  briefly blocks everyone else. Fine for a handful of users.
- **Last-write-wins.** No revision checks or locking — if two people edit the
  same plan, whoever saves last silently wins.
- **No user accounts.** Anyone who can reach the port can read and write plans;
  the shared privileged password gates a few specific actions, but it is not
  authentication and it does not identify who did what. Acceptable on the
  trusted LAN, not beyond it.
- **No HTTPS.**
- Request bodies over 100 MB are rejected (`413`); attachments over 15 MB.
- **Orphaned attachments accumulate.** Nothing cascades a plan delete into its
  photos (see above), and nothing sweeps up unreferenced files, so the
  `data\attachments` folder only ever grows. That is the intended trade.
- `index.json` is only rebuilt by `PUT` traffic. If plan files are hand-edited
  or dropped into `data\plans` by hand, the index will not know until that plan
  is next saved through the API.
