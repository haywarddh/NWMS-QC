<#
================================================================================
 qc-api.ps1 -- NWMS ISIR / QC plan service  (v0.6.2)
================================================================================

 WHAT THIS IS
 ------------
 A small single-file HTTP service that backs the QC planning front-end
 (the "qc" repo next door). It replaces the browser localStorage mock in
 qc\src\lib\plan-repository.ts with real files on disk, so plans are shared
 between machines instead of trapped in one browser profile.

 It does two jobs:
   1. JSON API under /api  (plans + FMEA library storage)
   2. Static file host for the built front-end (qc\dist) in production

 ARCHITECTURE
 ------------
 Same shape as the other NWMS PowerShell bridges: System.Net.HttpListener,
 one single-threaded GetContext loop. One request is handled at a time;
 the next caller waits. That is a known and accepted POC limitation.

 API CONTRACT (the front-end depends on these shapes exactly)
 ------------------------------------------------------------
   GET    /api/health       -> {"ok":true,"service":"qc-api","version":"<semver>",
                                "instance":"<label or empty>","pid":N,"plans":N}
   GET    /api/plans        -> PlanMeta[]   (newest updatedAt first)
   GET    /api/plans/all    -> PlanRecord[] (full records, dashboard roll-up)
   GET    /api/plans/{id}   -> PlanRecord   | 404 {"error":"not found"}
   PUT    /api/plans/{id}   -> body: full PlanRecord JSON; 200 {"ok":true}
   DELETE /api/plans/{id}   -> 200 {"ok":true}  (idempotent)
   GET    /api/library      -> {"templates":[...],"removedSeeds":[...]}
   PUT    /api/library      -> body same shape; 200 {"ok":true}
   GET    /api/privileged        -> {"configured":true|false}
   POST   /api/privileged/verify -> body {"password":"..."}; 200 {"ok":true|false}
   POST   /api/attachments       -> body: RAW image bytes, type from Content-Type;
                                    201 {"id":"<32 hex>","contentType":"image/jpeg","bytes":N}
   GET    /api/attachments/{id}  -> the image bytes with the stored Content-Type,
                                    or 404 {"error":"not found"}
   DELETE /api/attachments/{id}  -> 200 {"ok":true}  (idempotent)
   POST   /api/scans             -> body: RAW JSON bytes (an InspecVisionRow[]
                                    array); 201 {"id":"<32 hex>","bytes":N}
   GET    /api/scans/{id}        -> the JSON bytes, Content-Type application/json,
                                    or 404 {"error":"not found"}
   DELETE /api/scans/{id}        -> 200 {"ok":true}  (idempotent)
 All responses are JSON, UTF-8, application/json -- with TWO exceptions:
 GET /api/attachments/{id} answers with raw image bytes, and GET /api/scans/{id}
 answers with raw JSON bytes this service never parses. Errors are always
 JSON: {"error":"..."}.
 PlanMeta / PlanRecord shapes are defined by the TypeScript source of truth:
   qc\src\lib\plan-repository.ts  and  qc\src\lib\plan-store.tsx

 PRIVILEGED ACTIONS (one shared password, checked server-side)
 ------------------------------------------------------------
 The app deliberately has no user accounts. A handful of destructive or
 sign-off actions are gated by ONE shared password. The check happens HERE,
 never in the browser, so the secret is not sitting in the front-end bundle
 for anyone to read with View Source.
   * GET  /api/privileged        answers only "is a password set at all?".
                                 It never returns the password or its hash.
   * POST /api/privileged/verify answers {"ok":true} or {"ok":false}. A wrong
                                 password is a 200 with ok:false, NOT a 401 --
                                 it is an expected answer, not a transport
                                 error, and the front-end treats 401 as "the
                                 API is broken".
 The front-end never stores the password: it posts it once per unlock and
 keeps only a boolean in React state, so a page reload re-locks everything.

 ATTACHMENTS (why photos live OUTSIDE the plan body)
 --------------------------------------------------
 ISIRs need photographs: elcometer readings, packing, labelling, reference
 shots of a defect. The obvious implementation -- a data URL sitting on the
 plan record -- is wrong here, for two concrete reasons:
   * the WHOLE plan body is re-uploaded on every 700 ms autosave, so a couple
     of phone photos would turn each keystroke into a multi-MB PUT;
   * the front-end also mirrors the plan into browser localStorage, which
     caps out around 5-10 MB, so a handful of photos breaks it outright.
 So an image is POSTed ONCE to /api/attachments as raw bytes, stored as its
 own file, and the plan body carries only the returned id. Plans stay small
 and text-shaped; photos are fetched separately by the browser (and cached
 hard -- see below).

 Rules, all enforced in the handlers below:
   * Accepted types: image/jpeg, image/png, image/webp ONLY. Anything else is
     415. This is an evidence store for the QC app, not general file hosting.
   * 15 MB cap per attachment (413 over it). The browser downscales before
     upload, so this is headroom, not the expected size.
   * Ids are SERVER-generated -- 32 hex chars from a crypto RNG. A
     client-supplied id is never trusted, and on read/delete the id must match
     ^[a-f0-9]{32}$ exactly (400 otherwise). That is the path-traversal guard
     for data\attachments\<id>.<ext>.
   * The file EXTENSION is the type record, so there is no sidecar metadata
     file to keep in step: a GET resolves the file by trying jpg/png/webp and
     maps whichever exists back to its Content-Type.
   * GET sends Cache-Control: public, max-age=31536000, immutable. Ids are
     unique and content never changes under an id, so the browser can keep a
     photo forever.
   * Attachments are deliberately NOT cascade-deleted when a plan is deleted.
     An amended revision can reference the SAME photo ids as the plan it was
     copied from, so cascading would destroy evidence still in use elsewhere.
     Orphaned files are cheap (a few MB of disk); destroyed evidence is not.
     If that ever needs sweeping up, it wants a deliberate reference-counting
     pass across every plan, not a delete hook.

 SCAN DATA (why InspecVision scans live OUTSIDE the plan body, same as photos)
 ------------------------------------------------------------------------
 One PMP can be satisfied by an InspecVision 3D-scan check of many dimensions
 at once, rather than one manually-measured value. InspecVision's own export
 is itself cumulative -- it keeps appending to the same file until someone
 archives it on their end -- so re-uploading it will substantially overlap a
 prior upload, and a scan attached to a long-lived plan can accumulate to
 thousands of rows. That is the same "too big, too often, to live in the
 autosaved plan body" shape as photos (see ATTACHMENTS above), so this store
 follows the identical pattern: a blob is POSTed ONCE per merge, and the plan
 body carries only the returned id.
   * It differs from attachments in one respect: a scan REPLACES its PMP's
     reference on every re-upload rather than accumulating new references,
     because the front end fetches whatever blob is already stored, merges
     the freshly parsed rows in (deduplicated on Name + Inspection date), and
     POSTs the merged result as a NEW blob. The old blob becomes an orphan --
     never deleted, for exactly the reason attachments are never
     cascade-deleted: a frozen prior plan revision may still reference it.
   * This service never parses a scan's contents. It is an opaque JSON blob
     store, exactly like attachments are an opaque image store -- POST does
     only a cheap "does this start with '['" sanity check, never a full
     ConvertFrom-Json, for the same PS 5.1 large/deep-JSON reason plan bodies
     are stored as raw strings (see DATA LAYOUT below).
   * One content type only (application/json), so there is no magic-byte
     sniff and no multi-extension resolve -- see Resolve-ScanPath.
   * 25 MB cap per blob, not 15 MB like attachments: there is no client-side
     downscaling step for this data the way there is for a photo, and it only
     grows over a plan's life.

 DATA LAYOUT (under -DataDir, default .\data next to this script)
 ----------------------------------------------------------------
   plans\<id>.json   one full PlanRecord per file, stored as the RAW request
                     body string, byte-for-byte. We NEVER round-trip plan
                     bodies through ConvertFrom-Json/ConvertTo-Json --
                     PowerShell 5.1 mangles deep/large JSON (type coercion,
                     depth truncation), and plan bodies carry multi-MB
                     drawing data URLs.
   plans\index.json  PlanMeta[] (newest updatedAt first). The ONLY thing we
                     ever parse out of a plan body is record.meta, to keep
                     this index current.
   attachments\<id>.jpg|.png|.webp
                     one uploaded photo per file. <id> is server-generated
                     (32 hex chars) and the extension IS the stored content
                     type -- no sidecar metadata. Plans reference these by id
                     only; see ATTACHMENTS above.
   scans\<id>.json   one merged, deduplicated InspecVision dataset per file.
                     <id> is server-generated (32 hex chars); content is
                     always application/json, so unlike attachments there is
                     only one possible extension. One live reference per PMP
                     (Pmp.inspecVisionScan.blobId) -- see SCAN DATA above.
   library.json      raw body of the last PUT /api/library.
   settings.json     {"privilegedPasswordHash":"<hex sha256>","updatedAt":"..."}
                     Created on first run from the default password
                     "nwms-quality", with a warning on the console. Only the
                     SHA-256 hash is ever stored -- to change the password,
                     drop a new hash in (see README) and restart.
   qc-api.lock       the service lock (see MAINTENANCE NOTES below). Held open
                     with FileShare::None for the whole life of the process and
                     deleted on a clean stop. It lives in the DATA folder, not
                     next to the script, because what it protects is the DATA:
                     one lock per data folder is exactly the rule we want.

 MAINTENANCE NOTES FOR DAVE
 --------------------------
 * Written for Windows PowerShell 5.1 -- no ternary, no ??, no && chains.
 * All file writes go through Write-FileAtomic (write .tmp, then move over
   the target) so a crash mid-write can't leave a half-written JSON file.
 * All file IO is UTF-8 WITHOUT a byte-order mark. A BOM at the front of a
   JSON response corrupts JSON.parse in the browser.
 * The listener prefix is http://<ListenAddress>:<port>/. The default,
   localhost, binds unelevated and is reachable only from this machine -- which
   is right for local development. -ListenAddress "+" binds EVERY interface,
   which is what the NW-APPSERVER deployment needs, and http.sys refuses that
   unless the process is elevated OR the exact URL has been reserved once:
       netsh http add urlacl url=http://+:<port>/ user=DOMAIN\ServiceAccount
   $listener.Start() below turns that one specific failure into a plain-English
   explanation instead of a raw .NET "Access is denied", because it is the most
   likely first-deployment stumble.
 * A LAN-exposed instance also needs an inbound firewall rule for the port,
   scoped to the DOMAIN profile. The trap, learned on the Planner: if the
   machine's active network is classified Private or Public instead of Domain,
   a Domain-profile rule silently never matches and connections are DROPPED,
   not refused -- which looks exactly like a timeout and sends you hunting the
   wrong fault. Check with Get-NetConnectionProfile before believing anything.
 * -InstanceLabel is printed in the startup banner and returned by /api/health
   as "instance", so a LIVE window and a DEV window (and their health replies)
   are distinguishable at a glance. Two identical black console windows is how
   someone stops, or publishes over, the wrong one.
   The label is ALSO stamped on the front of every request-log line, and a
   fuller identity line is re-printed every 25 requests. That is not decoration:
   the banner above scrolls out of view within seconds of real use, and without
   those two the LIVE window becomes an unlabelled wall of log. Do not tidy
   them away.
 * ONE service per data folder, enforced: an EXCLUSIVE lock is taken on
   <DataDir>\qc-api.lock before the listener starts and held for the process
   lifetime. Two services sharing one data folder would interleave writes to
   plans\index.json and lose entries. If the lock cannot be taken the service
   says so and exits WITHOUT starting the listener.
   Finding the holder: netstat / Get-NetTCPConnection are useless here, because
   http.sys reports the listening socket as owned by PID 4 ("System"). Look at
   command lines instead:
       Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
         Where-Object { $_.CommandLine -like '*qc-api.ps1*' }
   If that instance was started elevated, you need an elevated session both to
   see its command line and to stop it.
 * Stop with Ctrl+C. The finally block below shuts the listener down and
   releases the service lock.
================================================================================
#>

[CmdletBinding()]
param(
    # TCP port to listen on. The Vite dev server proxies /api to this port.
    [int]$Port = 8791,

    # Folder holding the built front-end (index.html, assets\...).
    # Default: the sibling qc repo's dist folder, resolved relative to this
    # script's own location -- NOT the current directory, so the service
    # behaves the same no matter where it is started from.
    [string]$WebRoot = '',

    # Folder where plan/library JSON lives. Default: .\data next to script.
    [string]$DataDir = '',

    # Which network interface to bind. 'localhost' (the default) is reachable
    # only from this machine and binds without any privilege at all -- the right
    # default, so an accidental bare invocation never puts an unauthenticated
    # app on the LAN. '+' binds EVERY interface, which is what NW-APPSERVER
    # needs, and needs Administrator or a pre-registered urlacl to do it (see
    # MAINTENANCE NOTES above; the Start() failure below explains it in place).
    # A specific hostname or IP also works if you ever want to bind just one NIC.
    [string]$ListenAddress = 'localhost',

    # Cosmetic but load-bearing in practice: printed in the startup banner and
    # returned by /api/health as "instance". Blank (the default, and what any
    # ad-hoc invocation gets) shows nothing; the real launchers pass 'LIVE' or
    # 'DEV' explicitly, exactly as the Planner's sage-bridge.ps1 does, so two
    # otherwise identical black windows can be told apart before someone stops
    # the wrong one.
    [string]$InstanceLabel = ''
)

# Make cmdlet errors terminating so the per-request try/catch below turns any
# unexpected failure into a clean 500 response instead of a half-dead loop.
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Service identity
# ------------------------------------------------------------------------------
$ServiceName    = 'qc-api'
$ServiceVersion = '0.9.0'   # surfaced in /api/health and the startup banner

# Tag stamped on the front of EVERY console line the request loop writes, built
# once here rather than per request. An unlabelled ad-hoc run gets no tag at all,
# so its output is byte-for-byte what it always was.
$RequestLogTag = ''
if (-not [string]::IsNullOrWhiteSpace($InstanceLabel)) {
    $RequestLogTag = '[' + $InstanceLabel + '] '
}

# ------------------------------------------------------------------------------
# Resolve paths (all relative defaults hang off the script's own folder)
# ------------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($WebRoot)) {
    # ..\qc\dist\client, not ..\qc\dist. The build writes client\ (index.html,
    # assets\, fonts\) beside server\, and dist\ itself holds no index.html --
    # so pointing here would pass the "folder exists" check, print a reassuring
    # banner, and then 404 every page with no clue why.
    $WebRoot = Join-Path $PSScriptRoot '..\qc\dist\client'
}
$WebRoot = [System.IO.Path]::GetFullPath($WebRoot)

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $PSScriptRoot 'data'
}
$DataDir = [System.IO.Path]::GetFullPath($DataDir)

$PlansDir       = Join-Path $DataDir 'plans'
$IndexPath      = Join-Path $PlansDir 'index.json'
$LibraryPath    = Join-Path $DataDir 'library.json'
$SettingsPath   = Join-Path $DataDir 'settings.json'
$AttachmentsDir = Join-Path $DataDir 'attachments'
$ScansDir       = Join-Path $DataDir 'scans'

# The service lock. Deliberately inside the DATA folder: the thing being
# protected is this data, so "one holder per data folder" is precisely the rule,
# and a LIVE and a DEV instance with separate data folders are free to run side
# by side. See the lock block in Main.
$LockPath       = Join-Path $DataDir 'qc-api.lock'

# Create the data folders up front so every handler can assume they exist.
$null = New-Item -ItemType Directory -Force -Path $DataDir
$null = New-Item -ItemType Directory -Force -Path $PlansDir
$null = New-Item -ItemType Directory -Force -Path $AttachmentsDir
$null = New-Item -ItemType Directory -Force -Path $ScansDir

# UTF-8 encoder WITHOUT a BOM. [System.Text.Encoding]::UTF8 writes a BOM via
# WriteAllText, which would corrupt JSON parsing in the browser -- always use
# this instance for file writes.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Plan bodies can be several MB (drawings embedded as data URLs). Refuse only
# genuinely absurd requests.
$MaxBodyBytes = 100MB

# Per-attachment cap. The browser downscales photos before uploading, so a
# real ISIR photo lands well under a megabyte; 15 MB is headroom for an
# un-downscaled phone original, not the expected size.
$MaxAttachmentBytes = 15MB

# Per-scan-blob cap. Unlike photos there is no client-side downscaling step --
# a merged InspecVision dataset only grows over a plan's life as more runs get
# folded in. Twenty-odd named columns as a flat JSON array of objects runs
# roughly 300-600 bytes/row, so even a pessimistic 20,000-row lifetime
# accumulation lands under 12 MB -- 25 MB is comfortable headroom, not the
# expected size, same spirit as $MaxAttachmentBytes above.
$MaxScanBytes = 25MB

# Password used to SEED data\settings.json the very first time the service
# runs. It is not a fallback: once settings.json exists only the hash in that
# file is ever consulted, so changing the file changes the password. Kept in
# plain sight on purpose -- it is a starter value the operator is told (loudly,
# on the console) to replace.
$DefaultPrivilegedPassword = 'nwms-quality'

# This message contains an em dash. It is built from a character code so this
# script file stays pure ASCII -- PowerShell 5.1 misreads BOM-less UTF-8
# source files as ANSI, which would garble a literal em dash.
$WebRootMissingMessage = 'web root not built yet ' + [char]0x2014 + ' run npm run build in the qc repo'

# The complete PlanMeta field list, in canonical order, straight from
# qc\src\lib\plan-repository.ts. The index rebuild copies exactly these
# fields (and only the ones actually present) out of an incoming record's
# meta object. If PlanMeta grows a field, add it here too.
$PlanMetaFields = @(
    'id', 'title', 'status', 'partNumber', 'customer', 'drawingRef', 'issue',
    'owner', 'revision', 'createdAt', 'updatedAt',
    'issuedAt', 'issuedBy', 'notes',
    'submittedAt', 'submittedBy', 'customerContact', 'approvalRef',
    'decidedAt', 'decidedBy', 'approvalNotes',
    'archivedFrom', 'unarchivedAt', 'unarchivedBy', 'unarchivedFrom',
    'pmpCount', 'evidenceCount'
)

# ==============================================================================
# Small shared helpers
# ==============================================================================

# One console line per request: instance, timestamp, method, path, status,
# duration. The instance tag LEADS the line deliberately -- once the startup
# banner has scrolled away it is the only thing left saying whether this window
# is LIVE or DEV, and a left-aligned tag can be read straight down the edge of a
# screenful of log without reading the lines themselves.
function Write-RequestLog {
    param([string]$Method, [string]$Path, [int]$StatusCode, [int]$DurationMs)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ('{0}{1}  {2,-7} {3}  ->  {4}  ({5} ms)' -f $RequestLogTag, $stamp, $Method, $Path, $StatusCode, $DurationMs)
}

# Builds {"error":"..."} with the message properly JSON-escaped.
# ConvertTo-Json on a bare string returns it quoted and escaped -- handy.
function New-ErrorBody {
    param([string]$Message)
    return '{"error":' + (ConvertTo-Json -InputObject $Message) + '}'
}

# Lowest-level response writer. Sets status/headers, writes the body (unless
# the request was a HEAD, which must get identical headers but no body), and
# closes the stream. Returns the status code so callers can hand it up the
# chain for the request log.
#
# The body has ALWAYS been a byte[] here -- Send-Json is just a wrapper that
# encodes a string first -- so binary responses (attachment photos) need no
# special path: hand it the bytes straight off disk and nothing round-trips
# through a string, which would corrupt a JPEG.
#
# -CacheControl is optional and only used by the attachment reads, whose ids
# are unique and immutable. Everything else deliberately sends no caching
# header at all, so plan/library JSON is never served stale.
function Send-Bytes {
    param($Context, [int]$StatusCode, [string]$ContentType, [byte[]]$Bytes, [string]$CacheControl = '', [switch]$NoSniff)
    $response = $Context.Response
    $response.StatusCode      = $StatusCode
    $response.ContentType     = $ContentType
    $response.ContentLength64 = $Bytes.Length
    if (-not [string]::IsNullOrWhiteSpace($CacheControl)) {
        # Must be set before the first OutputStream.Write -- HttpListener
        # flushes the headers as soon as any body byte goes out.
        $response.AddHeader('Cache-Control', $CacheControl)
    }
    if ($NoSniff) {
        $response.AddHeader('X-Content-Type-Options', 'nosniff')
    }
    if ($Context.Request.HttpMethod -ne 'HEAD') {
        $response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    }
    $response.OutputStream.Close()
    return $StatusCode
}

# JSON response helper -- every /api response goes through here.
function Send-Json {
    param($Context, [int]$StatusCode, [string]$Json)
    $bytes = $Utf8NoBom.GetBytes($Json)
    return (Send-Bytes -Context $Context -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Bytes $bytes)
}

# Shared 405 response for any route hit with the wrong HTTP method.
function Send-MethodNotAllowed {
    param($Context)
    return (Send-Json -Context $Context -StatusCode 405 -Json (New-ErrorBody 'method not allowed'))
}

# Atomic-ish file write: write the full content to <file>.tmp, then move the
# tmp file over the real one. Move-Item within one volume is a rename, so
# readers either see the old complete file or the new complete file -- never
# a half-written one. Always UTF-8, no BOM.
function Write-FileAtomic {
    param([string]$Path, [string]$Content)
    $tmpPath = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmpPath, $Content, $Utf8NoBom)
    Move-Item -LiteralPath $tmpPath -Destination $Path -Force
}

# Binary twin of Write-FileAtomic, for attachment uploads. Same .tmp + move
# discipline (the maintenance note above says ALL writes work this way, and
# that should stay true), but WriteAllBytes -- no encoder anywhere near it,
# because an image is not text and must not be touched by one.
function Write-FileAtomicBytes {
    param([string]$Path, [byte[]]$Bytes)
    # The folder is made at startup, but a service can outlive its data dir --
    # someone tidies a temp folder, a sync tool moves it. Re-creating here is
    # free and turns "500 with the server's full path in the reply" into a
    # write that simply works.
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }
    $tmpPath = $Path + '.tmp'
    [System.IO.File]::WriteAllBytes($tmpPath, $Bytes)
    Move-Item -LiteralPath $tmpPath -Destination $Path -Force
}

# The first bytes of a file, which say what it REALLY is. The Content-Type
# header is a claim by the client; this is evidence storage, so the claim is
# checked. A mislabelled upload would otherwise sit in an ISIR until someone
# opened the report months later and found a broken image.
function Test-ImageMagic {
    param([byte[]]$Bytes, [string]$Extension)
    if ($Bytes.Length -lt 12) { return $false }
    if ($Extension -eq 'jpg') {
        return ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF)
    }
    if ($Extension -eq 'png') {
        return ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and
                $Bytes[3] -eq 0x47 -and $Bytes[4] -eq 0x0D -and $Bytes[5] -eq 0x0A -and
                $Bytes[6] -eq 0x1A -and $Bytes[7] -eq 0x0A)
    }
    if ($Extension -eq 'webp') {
        # "RIFF" .... "WEBP"
        return ($Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46 -and $Bytes[3] -eq 0x46 -and
                $Bytes[8] -eq 0x57 -and $Bytes[9] -eq 0x45 -and $Bytes[10] -eq 0x42 -and $Bytes[11] -eq 0x50)
    }
    return $false
}

# Reads the whole request body as a UTF-8 string. Bodies can be several MB
# (drawing data URLs); that is fine, ReadToEnd handles it.
function Read-RequestBody {
    param($Context)
    $reader = New-Object System.IO.StreamReader($Context.Request.InputStream, [System.Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}

# Reads the whole request body as RAW BYTES, with a hard cap applied WHILE
# reading rather than after, so an oversized upload is abandoned instead of
# being buffered in full first.
#
# This must never go through Read-RequestBody: that decodes the stream as
# UTF-8 text, and every byte sequence that is not valid UTF-8 (i.e. most of a
# JPEG) would come back as U+FFFD replacement characters. The image would be
# silently destroyed -- it would still "save", just not be an image any more.
#
# Returns $null when the body exceeds $MaxBytes (caller answers 413).
# Otherwise returns the byte[] -- note the leading comma on the return:
# PowerShell unrolls an array returned from a function, so a bare
# "return $bytes" would hand the caller an object[] of ~15 million boxed
# bytes. ",$bytes" wraps it, PowerShell unwraps exactly one level, and the
# byte[] arrives intact.
function Read-RequestBytes {
    param($Context, [int]$MaxBytes)

    # Named $bodyStream, NOT $input: $input is a PowerShell automatic variable
    # (the pipeline enumerator) and assigning to it inside a function is a
    # subtle way to break things.
    $bodyStream = $Context.Request.InputStream

    # Pre-size the buffer when the client declared a length (it always does
    # for a fetch() with a Blob body); -1 means chunked, so start small.
    $declared = [int64]$Context.Request.ContentLength64
    $initial  = 65536
    if ($declared -gt 0 -and $declared -lt $MaxBytes) { $initial = [int]$declared }

    $memory = New-Object System.IO.MemoryStream($initial)
    try {
        $chunk = New-Object byte[] 81920
        while ($true) {
            $read = $bodyStream.Read($chunk, 0, $chunk.Length)
            if ($read -le 0) { break }
            if (($memory.Length + $read) -gt $MaxBytes) { return $null }
            $memory.Write($chunk, 0, $read)
        }
        return ,$memory.ToArray()
    }
    finally {
        $memory.Dispose()
    }
}

# SHA-256 of a string's UTF-8 bytes, returned as lower-case hex (64 chars).
# Used for the privileged password: the plaintext is hashed the moment it
# arrives and only the hash is ever compared or written to disk.
function Get-Sha256Hex {
    param([string]$Text)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Same BOM-less UTF-8 encoder used for every file write, so the bytes
        # hashed here match the bytes a password would have on disk.
        $digest  = $hasher.ComputeHash($Utf8NoBom.GetBytes($Text))
        $builder = New-Object System.Text.StringBuilder
        foreach ($byte in $digest) {
            $null = $builder.Append($byte.ToString('x2'))
        }
        return $builder.ToString()
    }
    finally {
        # SHA256Managed holds unmanaged state -- always dispose it, even on
        # the error path, or a long-running loop leaks handles.
        $hasher.Dispose()
    }
}

# Plan ids come from crypto.randomUUID() in the browser, so letters, digits
# and hyphens are the only legal characters. Anything else (dots, slashes,
# percent tricks) is rejected before it can touch the filesystem -- this is
# the path-traversal guard for plans\<id>.json.
function Test-PlanId {
    param([string]$Id)
    return ($Id -match '^[A-Za-z0-9-]+$')
}

# ==============================================================================
# Attachment helpers (see the ATTACHMENTS section in the header block)
# ==============================================================================

# The three accepted image types, each mapped to the file extension that
# records it. This table is the single source of truth for both directions:
# POST uses it to accept/reject and pick an extension, GET uses it to turn the
# extension found on disk back into a Content-Type header.
$AttachmentTypes = [ordered]@{
    'image/jpeg' = 'jpg'
    'image/png'  = 'png'
    'image/webp' = 'webp'
}

# Normalises a raw Content-Type header ('image/jpeg; charset=binary', odd
# casing, stray spaces) down to the bare lower-case media type.
function Get-NormalizedContentType {
    param([string]$ContentType)
    $value = ''
    if ($null -ne $ContentType) { $value = [string]$ContentType }
    $semicolon = $value.IndexOf(';')
    if ($semicolon -ge 0) { $value = $value.Substring(0, $semicolon) }
    return $value.Trim().ToLowerInvariant()
}

# Extension for an accepted image type, or '' if the type is not one of the
# three. '' is the caller's signal to answer 415.
function Get-AttachmentExtension {
    param([string]$ContentType)
    $type = Get-NormalizedContentType -ContentType $ContentType
    if ($AttachmentTypes.Contains($type)) { return [string]$AttachmentTypes[$type] }
    return ''
}

# A fresh server-generated id: 16 crypto-random bytes as 32 lower-case hex
# chars. Deliberately NOT a client-supplied name and not sequential -- an id
# is the only thing guarding a photo, so it must not be guessable by counting.
function New-AttachmentId {
    $raw = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($raw)
    }
    finally {
        # Same discipline as Get-Sha256Hex: these hold unmanaged state, and a
        # long-running loop that skips Dispose leaks handles.
        $rng.Dispose()
    }
    $builder = New-Object System.Text.StringBuilder
    foreach ($byte in $raw) {
        $null = $builder.Append($byte.ToString('x2'))
    }
    return $builder.ToString()
}

# The path-traversal guard for data\attachments\<id>.<ext>. -cmatch (case
# SENSITIVE) on purpose: ids are generated lower-case, and -match would let
# 'ABC...' through, which is a different string being treated as the same
# file by the case-insensitive Windows filesystem.
function Test-AttachmentId {
    param([string]$Id)
    return ($Id -cmatch '^[a-f0-9]{32}$')
}

# Finds the stored file for an id by trying each accepted extension -- the
# extension IS the type record, which is why there is no sidecar metadata
# file to fall out of step. Returns '' when nothing is stored under that id.
# Callers MUST have run Test-AttachmentId first.
function Resolve-AttachmentPath {
    param([string]$Id)
    foreach ($extension in $AttachmentTypes.Values) {
        $candidate = Join-Path $AttachmentsDir ($Id + '.' + $extension)
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return ''
}

# Reverse lookup: file extension (no dot, lower-case) -> Content-Type.
function Get-AttachmentContentType {
    param([string]$Extension)
    foreach ($type in $AttachmentTypes.Keys) {
        if ([string]$AttachmentTypes[$type] -eq $Extension) { return [string]$type }
    }
    return 'application/octet-stream'
}

# --- Scan data (InspecVision) -------------------------------------------------
# A second, simpler blob store alongside attachments: one content type
# (application/json) instead of three, so there is only one possible
# extension and no magic-byte sniff to run. Deliberately its own set of
# functions rather than reusing the attachment ones directly -- the bodies
# would be identical for New-*Id, but a maintainer reading Invoke-ScanPost
# should not have to wonder why it calls something named for attachments.

# Same generation as New-AttachmentId: 16 crypto-random bytes as 32 lower-case
# hex chars. Not client-supplied, not sequential -- the id is the only thing
# guarding a scan blob.
function New-ScanId {
    $raw = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($raw)
    }
    finally {
        $rng.Dispose()
    }
    $builder = New-Object System.Text.StringBuilder
    foreach ($byte in $raw) {
        $null = $builder.Append($byte.ToString('x2'))
    }
    return $builder.ToString()
}

# The path-traversal guard for data\scans\<id>.json. Case-sensitive, same
# reasoning as Test-AttachmentId.
function Test-ScanId {
    param([string]$Id)
    return ($Id -cmatch '^[a-f0-9]{32}$')
}

# Unlike Resolve-AttachmentPath there is only one possible extension -- content
# is always JSON -- so no try-each-extension loop is needed. Callers MUST have
# run Test-ScanId first.
function Resolve-ScanPath {
    param([string]$Id)
    $candidate = Join-Path $ScansDir ($Id + '.json')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return ''
}

# ==============================================================================
# Plan index maintenance
# ==============================================================================
# The index (plans\index.json) is the ONLY place we ever parse and re-emit
# JSON, and it only ever holds flat PlanMeta objects, which PS 5.1 can
# round-trip safely. Full plan bodies are never round-tripped.

# Loads the index as an array of objects. Missing or unreadable -> empty.
function Read-PlanIndex {
    if (-not (Test-Path -LiteralPath $IndexPath)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($IndexPath)
        # TRAP (PowerShell 5.1): ConvertFrom-Json returns the JSON array as a
        # PSObject-WRAPPED array, and @(...) does NOT unroll that wrapper -- it
        # becomes a one-element array whose single element is the whole old
        # index. Downstream that element then re-serializes as a corrupt
        # {"value":[...],"Count":n} blob (real incident, 2026-08-16). foreach
        # DOES enumerate the wrapper properly, so copy element-by-element into
        # a fresh list and return a plain object array.
        $parsed = ConvertFrom-Json -InputObject $raw
        $entries = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $parsed) { $entries.Add($item) }
        return $entries.ToArray()
    }
    catch {
        Write-Host ('WARNING: could not parse ' + $IndexPath + ' - treating index as empty. ' + $_.Exception.Message)
        return @()
    }
}

# Serializes the given entries back to plans\index.json.
function Save-PlanIndex {
    param($Entries)
    $list = @($Entries)
    if ($list.Count -eq 0) {
        $json = '[]'
    }
    else {
        # CRITICAL (PowerShell 5.1 single-element collapse bug): the array
        # MUST be wrapped in @(...) and passed via -InputObject, never piped.
        # Piping unrolls the array element-by-element, so a one-record index
        # would serialize as a bare {...} instead of [ {...} ] and the
        # front-end's "PlanMeta[]" parse would break.
        $json = ConvertTo-Json -InputObject @($list) -Depth 6
    }
    Write-FileAtomic -Path $IndexPath -Content $json
}

# Copies exactly the known PlanMeta fields (in canonical order) out of an
# incoming record's meta object into a fresh ordered hashtable. Fields the
# browser did not send (optional ones like issuedAt) are omitted entirely,
# matching what JSON.stringify produced on the way in.
function Build-PlanMetaEntry {
    param($Meta)
    $entry = [ordered]@{}
    foreach ($field in $PlanMetaFields) {
        $property = $Meta.PSObject.Properties[$field]
        if ($null -ne $property) {
            $entry[$field] = $property.Value
        }
    }
    return $entry
}

# After a PUT: replace (or insert) this plan's index entry and re-sort the
# whole index newest-updatedAt-first.
function Update-PlanIndex {
    param($Meta)
    $entry    = Build-PlanMetaEntry -Meta $Meta
    $existing = @(Read-PlanIndex)

    $rebuilt = [System.Collections.Generic.List[object]]::new()
    $rebuilt.Add($entry)
    foreach ($old in $existing) {
        if ([string]$old.id -ne [string]$entry['id']) {
            $rebuilt.Add($old)
        }
    }

    # ISO-8601 timestamps sort correctly as plain strings, so a descending
    # string sort on updatedAt gives newest-first. The calculated property
    # works for both the ordered hashtable (new entry) and the PSCustomObjects
    # loaded from disk.
    $sorted = @($rebuilt | Sort-Object -Property @{ Expression = { [string]$_.updatedAt } } -Descending)
    Save-PlanIndex -Entries $sorted
}

# After a DELETE: drop the entry if present. Order of the survivors is
# already newest-first, so no re-sort needed. Skips the disk write entirely
# when the id was not in the index (idempotent delete).
function Remove-PlanFromIndex {
    param([string]$Id)
    $existing = @(Read-PlanIndex)
    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($old in $existing) {
        if ([string]$old.id -ne $Id) {
            $kept.Add($old)
        }
    }
    if ($kept.Count -ne $existing.Count) {
        Save-PlanIndex -Entries $kept
    }
}

# ==============================================================================
# Settings (data\settings.json -- the privileged password hash)
# ==============================================================================
# settings.json is a single flat OBJECT, not an array, so the PS 5.1
# PSObject-wrapped-array trap that bites Read-PlanIndex does not apply here --
# and no array round-trip is introduced below. Keep it that way.

# Writes settings.json (atomically, UTF-8 no BOM). Takes the already-hashed
# password: plaintext must never reach this function, let alone the disk.
# Emits nothing to the pipeline -- callers re-read through Read-Settings so
# there is exactly one shape of settings object in play.
function Save-Settings {
    param([string]$PasswordHash)
    $settings = [ordered]@{
        privilegedPasswordHash = $PasswordHash.ToLowerInvariant()
        updatedAt              = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd\THH:mm:ss.fff\Z')
    }
    $json = ConvertTo-Json -InputObject $settings -Depth 3
    Write-FileAtomic -Path $SettingsPath -Content $json
}

# Loads settings.json. On the very first run the file does not exist yet, so
# it is seeded from $DefaultPrivilegedPassword and the operator gets a loud
# one-line warning telling them to change it. An unparseable file is NOT
# overwritten (a hand-edit typo should not silently reset the password to the
# default) -- it returns $null, which leaves privileged actions locked.
function Read-Settings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Save-Settings -PasswordHash (Get-Sha256Hex -Text $DefaultPrivilegedPassword)
        Write-Host ('WARNING: privileged password set to the default - change it in ' + $SettingsPath)
    }
    try {
        $raw = [System.IO.File]::ReadAllText($SettingsPath)
        return (ConvertFrom-Json -InputObject $raw)
    }
    catch {
        Write-Host ('WARNING: could not parse ' + $SettingsPath + ' - privileged actions stay locked. ' + $_.Exception.Message)
        return $null
    }
}

# The stored hash, or '' when none is usable. '' is the "not configured"
# signal used by both privileged endpoints.
function Get-PrivilegedPasswordHash {
    $settings = Read-Settings
    if ($null -eq $settings) { return '' }
    $property = $settings.PSObject.Properties['privilegedPasswordHash']
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return ([string]$property.Value).Trim()
}

# ==============================================================================
# API handlers
# ==============================================================================

# GET /api/health -- liveness probe plus a quick plan count.
#
# "instance" carries -InstanceLabel ('' when none was passed), so a publisher or
# a monitoring check can confirm it is talking to LIVE and not DEV before it
# believes a version number. The label goes through ConvertTo-Json rather than
# being pasted between quotes: it comes from the command line, and a stray quote
# in it would otherwise produce a broken JSON reply.
function Invoke-HealthGet {
    param($Context)
    $planCount = @(Read-PlanIndex).Count
    $instance  = ConvertTo-Json -InputObject ([string]$InstanceLabel)
    # pid is here so a launcher can tell "the service I just started" from "a
    # stale service that was already answering". Without it, starting a second
    # instance against a locked data folder looks like success: the old one
    # replies, the new one exits, and the launcher says everything is fine.
    $json = '{"ok":true,"service":"' + $ServiceName + '","version":"' + $ServiceVersion + '","instance":' + $instance + ',"pid":' + $PID + ',"plans":' + $planCount + '}'
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# GET /api/plans -- the index file IS the response (kept sorted on write),
# so serve it raw with no parse/re-serialize round trip.
function Invoke-PlanListGet {
    param($Context)
    if (Test-Path -LiteralPath $IndexPath) {
        $json = [System.IO.File]::ReadAllText($IndexPath)
    }
    else {
        $json = '[]'
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# GET /api/plans/all -- full records for the dashboard roll-up. The raw
# per-plan files are concatenated into a JSON array STRING by hand
# ("[" + join(",") + "]") in index order. No object round-trip: each file is
# already valid JSON exactly as the browser sent it.
function Invoke-PlanAllGet {
    param($Context)
    $index  = @(Read-PlanIndex)
    $bodies = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $index) {
        $id = [string]$entry.id
        # Belt and braces: ids in the index were validated on the way in, but
        # never trust a hand-edited file enough to build paths from it.
        if (-not (Test-PlanId -Id $id)) { continue }
        $planPath = Join-Path $PlansDir ($id + '.json')
        if (Test-Path -LiteralPath $planPath) {
            $bodies.Add([System.IO.File]::ReadAllText($planPath))
        }
    }
    $json = '[' + ($bodies -join ',') + ']'
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# GET /api/plans/{id} -- serve the stored record byte-for-byte.
function Invoke-PlanGet {
    param($Context, [string]$Id)
    $planPath = Join-Path $PlansDir ($Id + '.json')
    if (-not (Test-Path -LiteralPath $planPath)) {
        return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody 'not found'))
    }
    $json = [System.IO.File]::ReadAllText($planPath)
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# PUT /api/plans/{id} -- store the raw body, then refresh the index from
# record.meta. The parse below is ONLY to read meta; what lands on disk is
# the untouched body string.
function Invoke-PlanPut {
    param($Context, [string]$Id)
    $request = $Context.Request

    if ($request.ContentLength64 -gt $MaxBodyBytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'request body too large'))
    }

    $body = Read-RequestBody -Context $Context
    if ([string]::IsNullOrWhiteSpace($body)) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'empty request body'))
    }

    # Parse purely to reach record.meta. (PS 5.1's ConvertFrom-Json lifts the
    # 2 MB JavaScriptSerializer default limit internally, so large bodies
    # parse fine -- just a little slowly.)
    $record = $null
    try {
        $record = ConvertFrom-Json -InputObject $body
    }
    catch {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'request body is not valid JSON'))
    }

    # A PlanRecord is { meta: {...}, state: {...} }. Validate just enough to
    # keep the index sane: meta must exist and meta.id must match the URL.
    $metaProperty = $null
    if ($null -ne $record) { $metaProperty = $record.PSObject.Properties['meta'] }
    if ($null -eq $metaProperty -or $null -eq $metaProperty.Value) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'record has no meta object'))
    }
    $meta = $metaProperty.Value

    $idProperty = $meta.PSObject.Properties['id']
    if ($null -eq $idProperty -or ([string]$idProperty.Value) -ne $Id) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'meta.id does not match the URL id'))
    }

    # Write the plan file first, then the index. If the index update failed
    # the plan is still safely stored, and the next PUT self-heals the index.
    $planPath = Join-Path $PlansDir ($Id + '.json')
    Write-FileAtomic -Path $planPath -Content $body
    Update-PlanIndex -Meta $meta

    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
}

# DELETE /api/plans/{id} -- idempotent: deleting something absent is still 200.
function Invoke-PlanDelete {
    param($Context, [string]$Id)
    $planPath = Join-Path $PlansDir ($Id + '.json')
    if (Test-Path -LiteralPath $planPath) {
        Remove-Item -LiteralPath $planPath -Force
    }
    Remove-PlanFromIndex -Id $Id
    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
}

# GET /api/library -- raw stored body, or the empty shape before first save.
function Invoke-LibraryGet {
    param($Context)
    if (Test-Path -LiteralPath $LibraryPath) {
        $json = [System.IO.File]::ReadAllText($LibraryPath)
    }
    else {
        $json = '{"templates":[],"removedSeeds":[]}'
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# PUT /api/library -- validate the shape lightly, then store the raw body.
function Invoke-LibraryPut {
    param($Context)
    $request = $Context.Request

    if ($request.ContentLength64 -gt $MaxBodyBytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'request body too large'))
    }

    $body = Read-RequestBody -Context $Context
    if ([string]::IsNullOrWhiteSpace($body)) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'empty request body'))
    }

    # Parse only to validate -- the raw string is what gets stored.
    $parsed = $null
    try {
        $parsed = ConvertFrom-Json -InputObject $body
    }
    catch {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'request body is not valid JSON'))
    }

    $templatesProperty = $null
    $removedProperty   = $null
    if ($null -ne $parsed) {
        $templatesProperty = $parsed.PSObject.Properties['templates']
        $removedProperty   = $parsed.PSObject.Properties['removedSeeds']
    }
    if ($null -eq $templatesProperty -or $null -eq $removedProperty) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'body must be {"templates":[...],"removedSeeds":[...]}'))
    }

    Write-FileAtomic -Path $LibraryPath -Content $body
    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
}

# GET /api/privileged -- "is a privileged password set at all?", nothing more.
# The front-end uses it to decide whether to show the unlock prompt. Neither
# the password nor its hash is ever included in the answer.
function Invoke-PrivilegedGet {
    param($Context)
    $storedHash = Get-PrivilegedPasswordHash
    if ([string]::IsNullOrWhiteSpace($storedHash)) {
        $json = '{"configured":false}'
    }
    else {
        $json = '{"configured":true}'
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json $json)
}

# POST /api/privileged/verify -- body {"password":"..."}.
# A WRONG password is 200 {"ok":false}, deliberately not 401: it is an
# expected answer, not a transport failure, and the front-end reads any non-2xx
# as "the API is broken" rather than "try again". 4xx here is reserved for a
# genuinely malformed request (not JSON, no password field).
function Invoke-PrivilegedVerifyPost {
    param($Context)
    $request = $Context.Request

    if ($request.ContentLength64 -gt $MaxBodyBytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'request body too large'))
    }

    $body = Read-RequestBody -Context $Context
    if ([string]::IsNullOrWhiteSpace($body)) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'empty request body'))
    }

    $parsed = $null
    try {
        $parsed = ConvertFrom-Json -InputObject $body
    }
    catch {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'request body is not valid JSON'))
    }

    $passwordProperty = $null
    if ($null -ne $parsed) { $passwordProperty = $parsed.PSObject.Properties['password'] }
    if ($null -eq $passwordProperty -or $null -eq $passwordProperty.Value) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'body must be {"password":"..."}'))
    }

    # Trim TRAILING CR/LF only -- that is a stray newline from a form or a
    # scanner, never part of the password. Leading and inner spaces are real
    # characters and must survive untouched.
    $supplied = ([string]$passwordProperty.Value).TrimEnd([char]13, [char]10)

    $storedHash = Get-PrivilegedPasswordHash
    if ([string]::IsNullOrWhiteSpace($storedHash)) {
        # No usable password on disk: nothing can match, so nothing unlocks.
        return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":false}')
    }

    # Compare the two full 64-char hex digests, case-insensitively. Comparing
    # hashes rather than plaintext keeps the compared length constant whatever
    # the caller sent, and leaks nothing about the real password's length.
    $suppliedHash = Get-Sha256Hex -Text $supplied
    if ([string]::Equals($suppliedHash, $storedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":false}')
}

# POST /api/attachments -- the body IS the image; there is no JSON envelope
# and no multipart form, because both would mean base64-ing or text-parsing
# binary data for no benefit. The Content-Type header states the type, the
# raw bytes follow, and the response hands back the id the plan will store.
function Invoke-AttachmentPost {
    param($Context)
    $request = $Context.Request

    # Type first: refusing an unsupported type before reading means a 20 MB
    # video upload is rejected on its header, not after buffering it.
    $extension = Get-AttachmentExtension -ContentType $request.ContentType
    if ($extension -eq '') {
        return (Send-Json -Context $Context -StatusCode 415 -Json (New-ErrorBody 'unsupported media type - attachments must be image/jpeg, image/png or image/webp'))
    }

    # Cheap pre-check on the declared length, then the real check inside
    # Read-RequestBytes, which enforces the cap as it reads. Both are needed:
    # a chunked upload declares no length at all.
    if ($request.ContentLength64 -gt $MaxAttachmentBytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'attachment too large - the limit is 15 MB'))
    }

    # A phone dropping Wi-Fi mid-upload is not a server fault. Catching it here
    # keeps the log honest: a real 500 in this handler means a real bug, and is
    # worth chasing. A 499 line is just someone walking out of range.
    try {
        $bytes = Read-RequestBytes -Context $Context -MaxBytes $MaxAttachmentBytes
    }
    catch [System.Net.HttpListenerException] {
        return 499
    }
    catch [System.IO.IOException] {
        return 499
    }
    if ($null -eq $bytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'attachment too large - the limit is 15 MB'))
    }
    if ($bytes.Length -eq 0) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'empty request body'))
    }
    # The header said one thing; the bytes have to agree.
    if (-not (Test-ImageMagic -Bytes $bytes -Extension $extension)) {
        return (Send-Json -Context $Context -StatusCode 415 -Json (New-ErrorBody 'the file content does not match the declared image type'))
    }

    # The id is minted HERE. Nothing the client sent influences the filename.
    $id       = New-AttachmentId
    $filePath = Join-Path $AttachmentsDir ($id + '.' + $extension)
    Write-FileAtomicBytes -Path $filePath -Bytes $bytes

    $contentType = Get-AttachmentContentType -Extension $extension
    $json = '{"id":"' + $id + '","contentType":"' + $contentType + '","bytes":' + $bytes.Length + '}'
    return (Send-Json -Context $Context -StatusCode 201 -Json $json)
}

# GET /api/attachments/{id} -- the one endpoint under /api that answers with
# something other than JSON. Bytes go out exactly as they came in: read with
# ReadAllBytes, handed to Send-Bytes as a byte[], never near a string.
function Invoke-AttachmentGet {
    param($Context, [string]$Id)

    $filePath = Resolve-AttachmentPath -Id $Id
    if ($filePath -eq '') {
        return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody 'not found'))
    }

    $extension   = [System.IO.Path]::GetExtension($filePath).TrimStart('.').ToLowerInvariant()
    $contentType = Get-AttachmentContentType -Extension $extension
    $bytes       = [System.IO.File]::ReadAllBytes($filePath)

    # Immutable caching is safe precisely because ids are unique and content
    # never changes under one: an edited photo is a NEW upload with a new id.
    # nosniff: the stored type is authoritative, so a browser must not go
    # guessing from content and decide these bytes are something executable.
    return (Send-Bytes -Context $Context -StatusCode 200 -ContentType $contentType -Bytes $bytes -CacheControl 'public, max-age=31536000, immutable' -NoSniff)
}

# DELETE /api/attachments/{id} -- idempotent, like the plan delete: removing
# something already absent is still a 200. Only ever called explicitly (the
# user removed a photo from a plan); nothing cascades into here when a plan
# is deleted, on purpose -- see ATTACHMENTS in the header block.
function Invoke-AttachmentDelete {
    param($Context, [string]$Id)
    $filePath = Resolve-AttachmentPath -Id $Id
    if ($filePath -ne '') {
        Remove-Item -LiteralPath $filePath -Force
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
}

# POST /api/scans -- the body IS the merged InspecVision row array as JSON
# bytes; no envelope, mirroring how attachments take raw image bytes. This
# service never parses InspecVision's row shape -- it is an opaque blob store,
# exactly like attachments are for images. See SCAN DATA in the header block.
function Invoke-ScanPost {
    param($Context)
    $request = $Context.Request

    if ($request.ContentLength64 -gt $MaxScanBytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'scan data too large - the limit is 25 MB'))
    }

    try {
        $bytes = Read-RequestBytes -Context $Context -MaxBytes $MaxScanBytes
    }
    catch [System.Net.HttpListenerException] {
        return 499
    }
    catch [System.IO.IOException] {
        return 499
    }
    if ($null -eq $bytes) {
        return (Send-Json -Context $Context -StatusCode 413 -Json (New-ErrorBody 'scan data too large - the limit is 25 MB'))
    }
    if ($bytes.Length -eq 0) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'empty request body'))
    }

    # Light sanity check ONLY -- the first non-whitespace byte must be '[',
    # since the front end always sends a JSON array. Deliberately NOT a full
    # ConvertFrom-Json parse: the same PS 5.1 large/deep-JSON risk that keeps
    # plan bodies stored as raw strings (see DATA LAYOUT) applies here too, and
    # a merged scan can run to thousands of rows.
    $firstChar = ''
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $ch = [char]$bytes[$i]
        if (-not [char]::IsWhiteSpace($ch)) { $firstChar = $ch; break }
    }
    if ($firstChar -ne '[') {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'scan data must be a JSON array'))
    }

    # The id is minted HERE. Nothing the client sent influences the filename.
    $id       = New-ScanId
    $filePath = Join-Path $ScansDir ($id + '.json')
    Write-FileAtomicBytes -Path $filePath -Bytes $bytes

    $json = '{"id":"' + $id + '","bytes":' + $bytes.Length + '}'
    return (Send-Json -Context $Context -StatusCode 201 -Json $json)
}

# GET /api/scans/{id} -- the bytes go out exactly as stored, same discipline
# as Invoke-AttachmentGet: read with ReadAllBytes, handed to Send-Bytes as a
# byte[], never near a string this service would have to parse.
function Invoke-ScanGet {
    param($Context, [string]$Id)
    $filePath = Resolve-ScanPath -Id $Id
    if ($filePath -eq '') {
        return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody 'not found'))
    }
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    # No immutable caching here, unlike attachments: a scan blob's id is
    # superseded (not edited) on every merge, so this is still safe to cache,
    # but the front end always fetches by the CURRENT id off a fresh Pmp, so
    # there is no benefit to hanging onto a stale response either.
    return (Send-Bytes -Context $Context -StatusCode 200 -ContentType 'application/json; charset=utf-8' -Bytes $bytes)
}

# DELETE /api/scans/{id} -- idempotent, exists for symmetry and any future
# maintenance sweep. The app itself never calls this in normal use: a fresh
# merge supersedes a PMP's reference rather than deleting the old blob -- see
# Pmp.inspecVisionScan's field comment in plan-store.tsx for why.
function Invoke-ScanDelete {
    param($Context, [string]$Id)
    $filePath = Resolve-ScanPath -Id $Id
    if ($filePath -ne '') {
        Remove-Item -LiteralPath $filePath -Force
    }
    return (Send-Json -Context $Context -StatusCode 200 -Json '{"ok":true}')
}

# ==============================================================================
# Static file serving (production: the built front-end from qc\dist)
# ==============================================================================

# Maps a lower-case file extension to a Content-Type header.
function Get-StaticContentType {
    param([string]$Extension)
    switch ($Extension) {
        '.html'  { return 'text/html; charset=utf-8' }
        '.js'    { return 'application/javascript; charset=utf-8' }
        # ES module extension. Browsers strictly enforce a JavaScript MIME type
        # for module scripts, including a module Worker -- pdf.js loads its
        # renderer that way. Without this case, .mjs fell to the default below
        # (application/octet-stream) and every PDF drawing upload failed with
        # "Failed to load module script: ... non-JavaScript MIME type", silent
        # everywhere except the browser console.
        '.mjs'   { return 'text/javascript; charset=utf-8' }
        '.css'   { return 'text/css; charset=utf-8' }
        '.map'   { return 'application/json; charset=utf-8' }
        '.json'  { return 'application/json; charset=utf-8' }
        '.svg'   { return 'image/svg+xml; charset=utf-8' }
        '.png'   { return 'image/png' }
        '.jpg'   { return 'image/jpeg' }
        '.jpeg'  { return 'image/jpeg' }
        '.ico'   { return 'image/x-icon' }
        '.woff'  { return 'font/woff' }
        '.woff2' { return 'font/woff2' }
        '.txt'   { return 'text/plain; charset=utf-8' }
        default  { return 'application/octet-stream' }
    }
}

# Reads a file off disk and sends it with the right Content-Type.
function Send-File {
    param($Context, [string]$FilePath)
    $bytes       = [System.IO.File]::ReadAllBytes($FilePath)
    $extension   = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $contentType = Get-StaticContentType -Extension $extension
    return (Send-Bytes -Context $Context -StatusCode 200 -ContentType $contentType -Bytes $bytes)
}

# Any non-/api GET (or HEAD) lands here.
#   * exact file under WebRoot        -> serve it
#   * no extension and no such file   -> serve index.html (SPA fallback, so
#                                        client-side routes survive a refresh)
#   * anything else                   -> 404
function Invoke-StaticRequest {
    param($Context, [string]$Path)

    $method = $Context.Request.HttpMethod
    if ($method -ne 'GET' -and $method -ne 'HEAD') {
        return (Send-MethodNotAllowed -Context $Context)
    }

    # Front-end not built yet (fresh clone, or dist wiped): explain instead
    # of a bare 404 so future-Dave knows exactly what to do.
    if (-not (Test-Path -LiteralPath $WebRoot -PathType Container)) {
        return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody $WebRootMissingMessage))
    }

    $relative = $Path.TrimStart('/')
    if ($relative -eq '') { $relative = 'index.html' }
    $relative = $relative.Replace('/', '\')

    # Resolve to a full path and confirm it is still INSIDE WebRoot. This is
    # the traversal guard for the static side: "..\..\secrets" resolves to
    # something outside the root prefix and is rejected.
    $candidate = $null
    try {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $WebRoot $relative))
    }
    catch {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'bad path'))
    }
    $rootPrefix = $WebRoot.TrimEnd('\') + '\'
    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'bad path'))
    }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Send-File -Context $Context -FilePath $candidate)
    }

    # SPA fallback: extensionless paths are client-side routes.
    $extension = [System.IO.Path]::GetExtension($candidate)
    if ($extension -eq '') {
        $indexFile = Join-Path $WebRoot 'index.html'
        if (Test-Path -LiteralPath $indexFile -PathType Leaf) {
            return (Send-File -Context $Context -FilePath $indexFile)
        }
    }

    return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody 'not found'))
}

# ==============================================================================
# Router
# ==============================================================================

# Dispatches one request to the right handler and returns the response status
# code for the request log. Route order matters: the exact /api/plans/all
# check must come BEFORE the /api/plans/{id} pattern, or "all" would be
# treated as a plan id.
function Invoke-Request {
    param($Context)

    $request = $Context.Request
    $method  = $request.HttpMethod

    # HEAD is routed exactly like GET; Send-Bytes suppresses the body.
    $routeMethod = $method
    if ($routeMethod -eq 'HEAD') { $routeMethod = 'GET' }

    # Decode %xx escapes once up front, so an encoded traversal attempt
    # (%2e%2e) is visible to the guards below as literal dots.
    $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)

    # ----- API routes ---------------------------------------------------------
    if ($path -eq '/api/health') {
        if ($routeMethod -eq 'GET') { return (Invoke-HealthGet -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -eq '/api/plans') {
        if ($routeMethod -eq 'GET') { return (Invoke-PlanListGet -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -eq '/api/plans/all') {
        if ($routeMethod -eq 'GET') { return (Invoke-PlanAllGet -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -match '^/api/plans/([^/]+)$') {
        $id = $Matches[1]
        if (-not (Test-PlanId -Id $id)) {
            return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'invalid plan id'))
        }
        if ($routeMethod -eq 'GET')    { return (Invoke-PlanGet    -Context $Context -Id $id) }
        if ($routeMethod -eq 'PUT')    { return (Invoke-PlanPut    -Context $Context -Id $id) }
        if ($routeMethod -eq 'DELETE') { return (Invoke-PlanDelete -Context $Context -Id $id) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -eq '/api/library') {
        if ($routeMethod -eq 'GET') { return (Invoke-LibraryGet -Context $Context) }
        if ($routeMethod -eq 'PUT') { return (Invoke-LibraryPut -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    # Both privileged routes are EXACT matches, so unlike /api/plans/all vs
    # /api/plans/{id} neither can shadow the other and the order is free.
    if ($path -eq '/api/privileged') {
        if ($routeMethod -eq 'GET') { return (Invoke-PrivilegedGet -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -eq '/api/privileged/verify') {
        # POST only: verification is not a GET, so the password can never end
        # up in a query string, a browser history entry or this service's log.
        if ($method -eq 'POST') { return (Invoke-PrivilegedVerifyPost -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    # Attachments. Same ordering rule as the plan routes: the exact
    # /api/attachments collection route is matched BEFORE the /{id} pattern.
    if ($path -eq '/api/attachments') {
        # POST only -- an upload is not a GET, and there is deliberately no
        # "list all attachments" endpoint: photos are reached through the plan
        # that references them, never browsed as a gallery of evidence.
        if ($method -eq 'POST') { return (Invoke-AttachmentPost -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -match '^/api/attachments/([^/]+)$') {
        $attachmentId = $Matches[1]
        if (-not (Test-AttachmentId -Id $attachmentId)) {
            return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'invalid attachment id'))
        }
        if ($routeMethod -eq 'GET')    { return (Invoke-AttachmentGet    -Context $Context -Id $attachmentId) }
        if ($routeMethod -eq 'DELETE') { return (Invoke-AttachmentDelete -Context $Context -Id $attachmentId) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    # Scan data (InspecVision). Same shape as attachments, same ordering rule.
    if ($path -eq '/api/scans') {
        # POST only -- same reasoning as attachments: no "list all scans"
        # endpoint, a scan blob is reached through the PMP that references it.
        if ($method -eq 'POST') { return (Invoke-ScanPost -Context $Context) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    if ($path -match '^/api/scans/([^/]+)$') {
        $scanId = $Matches[1]
        if (-not (Test-ScanId -Id $scanId)) {
            return (Send-Json -Context $Context -StatusCode 400 -Json (New-ErrorBody 'invalid scan id'))
        }
        if ($routeMethod -eq 'GET')    { return (Invoke-ScanGet    -Context $Context -Id $scanId) }
        if ($routeMethod -eq 'DELETE') { return (Invoke-ScanDelete -Context $Context -Id $scanId) }
        return (Send-MethodNotAllowed -Context $Context)
    }

    # Unknown /api path.
    if ($path -eq '/api' -or $path -like '/api/*') {
        return (Send-Json -Context $Context -StatusCode 404 -Json (New-ErrorBody 'not found'))
    }

    # ----- Everything else: the front-end -------------------------------------
    return (Invoke-StaticRequest -Context $Context -Path $path)
}

# ==============================================================================
# Main: take the service lock, start the listener, run the request loop
# ==============================================================================

$prefix           = 'http://' + $ListenAddress + ':' + $Port + '/'
$serviceStartedAt = Get-Date

# --- Service lock -------------------------------------------------------------
# Equivalent to the Planner's planner-service.lock, and for the same reason: two
# services pointed at one data folder would interleave writes to
# plans\index.json, and the loser's records would vanish from the list while
# still sitting on disk. The lock is a genuine exclusive OS file lock (a
# FileStream opened FileShare::None and never closed until the process ends), not
# a flag file that a crash could leave behind as a false positive.
#
# Taken BEFORE the listener starts, so a second instance fails on the thing that
# actually matters (the data) rather than binding a port first and then dying.
$lockStream = $null
try {
    $lockArgs = @(
        $LockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $lockStream = New-Object System.IO.FileStream -ArgumentList $lockArgs
}
catch {
    Write-Host ''
    Write-Host 'ERROR: another qc-api instance is already using this data folder.'
    Write-Host ('  Data folder : ' + $DataDir)
    Write-Host ('  Lock file   : ' + $LockPath)
    Write-Host ''
    Write-Host 'Two services sharing one data folder would interleave writes to'
    Write-Host 'plans\index.json and quietly lose records, so this one is stopping before'
    Write-Host 'it starts listening. Nothing has been changed.'
    Write-Host ''
    Write-Host 'This is a REAL exclusive file lock, not a stale leftover file: if you are'
    Write-Host 'seeing this, a process is holding it right now. Find it by COMMAND LINE,'
    Write-Host 'not by port -- http.sys reports the listening socket as owned by PID 4'
    Write-Host '("System"), which tells you nothing useful:'
    Write-Host ''
    Write-Host '    Get-CimInstance Win32_Process -Filter "Name=''powershell.exe''" |'
    Write-Host '      Where-Object { $_.CommandLine -like ''*qc-api.ps1*'' }'
    Write-Host ''
    Write-Host 'If that instance was started elevated, you need an elevated session both'
    Write-Host 'to see its command line and to stop it. To run a second instance on'
    Write-Host 'purpose (a DEV alongside LIVE), give it its own -DataDir and -Port.'
    Write-Host ''
    exit 1
}

# Stamp the lock file with who holds it. FileShare::None means nobody can read
# this while the service is running -- which is fine, because the case that
# needs it is the opposite one: a leftover lock file after a crash or a taskkill,
# where "which process was that, and since when?" is exactly the question. Flush
# immediately so the answer survives a hard kill.
$lockLines = @(
    ('ProcessId=' + $PID),
    ('Computer=' + $env:COMPUTERNAME),
    ('Instance=' + $InstanceLabel),
    ('Started=' + $serviceStartedAt.ToString('yyyy-MM-dd HH:mm:ss')),
    ('Listening=' + $prefix),
    ('DataDir=' + $DataDir)
)
$lockBytes = $Utf8NoBom.GetBytes(($lockLines -join "`r`n") + "`r`n")
$lockStream.SetLength(0)
$lockStream.Write($lockBytes, 0, $lockBytes.Length)
$lockStream.Flush()

# --- Listener -----------------------------------------------------------------
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    # A deliberately untyped catch rather than [System.Net.HttpListenerException]:
    # a .NET method that throws inside PowerShell 5.1 can arrive wrapped in a
    # MethodInvocationException, so the dependable test is the message text --
    # which carries the inner message either way -- not the exception type.
    $detail = $_.Exception.Message

    if ($detail -like '*Access is denied*' -and $ListenAddress -ne 'localhost') {
        # THE most likely first-deployment failure on NW-APPSERVER. The raw .NET
        # message says only "Access is denied", which sounds like a file
        # permission or a share problem and sends people looking in the wrong
        # place entirely. It is neither: it is http.sys refusing to hand this
        # process a non-localhost binding.
        Write-Host ''
        Write-Host ('ERROR: not allowed to listen on ' + $prefix + ' -- "Access is denied".')
        Write-Host ''
        Write-Host ('Nothing is wrong with the folder, the share or the data. Binding')
        Write-Host ('"' + $ListenAddress + '" means every caller on the network, and Windows treats that as a')
        Write-Host 'privileged operation: http.sys, not this script, is refusing it. There are'
        Write-Host 'exactly two ways to fix it:'
        Write-Host ''
        Write-Host '  1. Run the service from an ELEVATED PowerShell window ("Run as'
        Write-Host '     administrator"). Fixes this start only -- every future start then'
        Write-Host '     needs elevation too, which is why it is not the deployment answer.'
        Write-Host ''
        Write-Host '  2. Reserve the URL once for the account that runs the service, after'
        Write-Host '     which it starts unelevated forever. In an ELEVATED window, once:'
        Write-Host ''
        Write-Host ('       netsh http add urlacl url=' + $prefix + ' user=DOMAIN\ServiceAccount')
        Write-Host ''
        Write-Host '     Replace DOMAIN\ServiceAccount with the account that will actually'
        Write-Host '     run it. On NW-APPSERVER this is what "Configure Quality Records.ps1"'
        Write-Host '     does for you, alongside the firewall rule.'
        Write-Host ''
        Write-Host 'A reservation covers one EXACT url, so the line above is for this address'
        Write-Host 'and port only -- a different port (a DEV instance, say) needs its own.'
        Write-Host ''
        Write-Host 'To carry on locally in the meantime, start it with no -ListenAddress at'
        Write-Host 'all: localhost binds with no privileges whatsoever.'
        Write-Host ''
    }
    else {
        Write-Host ('ERROR: could not start listener on ' + $prefix + ' -- ' + $detail)
        Write-Host 'Is another instance already running on this port?'
    }

    # Release the lock on this path explicitly. The finally below belongs to the
    # request loop, which is never reached from here.
    $lockStream.Dispose()
    Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    exit 1
}

# --- Startup banner -----------------------------------------------------------
# The instance label is shouted, not whispered: on NW-APPSERVER a LIVE and a DEV
# window are otherwise two identical black rectangles, and that is how someone
# stops the wrong one. Same convention as the Planner's sage-bridge.ps1.
if ($InstanceLabel -eq 'LIVE') {
    Write-Host ''
    Write-Host '################################################################' -ForegroundColor Red
    Write-Host '###   !!!  THIS IS THE LIVE QUALITY RECORDS SERVER  !!!       ###' -ForegroundColor Red
    Write-Host '###   REAL ISIR RECORDS AND PHOTOGRAPHIC EVIDENCE            ###' -ForegroundColor Red
    Write-Host '###   DO NOT CLOSE THIS WINDOW UNLESS YOU MEAN TO STOP IT    ###' -ForegroundColor Red
    Write-Host '################################################################' -ForegroundColor Red
    Write-Host ''
}
elseif (-not [string]::IsNullOrWhiteSpace($InstanceLabel)) {
    Write-Host ''
    Write-Host '############################################################' -ForegroundColor Magenta
    Write-Host ('#   THIS IS THE ' + $InstanceLabel + ' INSTANCE -- NOT PRODUCTION') -ForegroundColor Magenta
    Write-Host '############################################################' -ForegroundColor Magenta
    Write-Host ''
}

$webRootExists = Test-Path -LiteralPath $WebRoot -PathType Container
$titleLine = ' ' + $ServiceName + '  v' + $ServiceVersion + '  --  NWMS ISIR / QC plan service'
if (-not [string]::IsNullOrWhiteSpace($InstanceLabel)) {
    $titleLine = ' [' + $InstanceLabel + ']  ' + $ServiceName + '  v' + $ServiceVersion + '  --  NWMS ISIR / QC plan service'
}
Write-Host '=============================================================='
Write-Host $titleLine
Write-Host '--------------------------------------------------------------'
Write-Host (' Listening : ' + $prefix)
if ($ListenAddress -eq 'localhost') {
    Write-Host '             (this machine only -- pass -ListenAddress "+" for the LAN)'
}
else {
    # Worth stating every single start: the app has no user accounts, so reach
    # equals full read/write access to every record.
    Write-Host '             (LAN-visible. This app has NO user authentication, so the'
    Write-Host '              firewall rule must stay Domain-profile and LAN-only.)'
}
Write-Host (' Data dir  : ' + $DataDir)
Write-Host (' Lock      : ' + $LockPath + '  (held, PID ' + $PID + ')')
if ($webRootExists) {
    Write-Host (' Web root  : ' + $WebRoot + '  (found -- serving front-end)')
}
else {
    Write-Host (' Web root  : ' + $WebRoot + '  (MISSING -- API only until the front-end is built)')
}
Write-Host (' Started   : ' + $serviceStartedAt.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Host ' Stop with Ctrl+C.'
Write-Host '=============================================================='

# --- Identity that survives the scroll ----------------------------------------
# Everything above is printed ONCE. This service also logs a line per request to
# the same console, so within seconds of real use the banner -- the only thing
# saying LIVE or DEV -- has scrolled out of view. On a Windows Terminal host it
# is worse than out of view: WT reports the console buffer as the same size as
# the window, so there is no console scrollback to scroll back through.
#
# So identity has to ride the output that keeps coming: the [LABEL] tag on every
# request line, plus this fuller reminder every so often. Nothing here relies on
# the window title, which sounds like the obvious answer and is not: under
# Windows Terminal the OS window title follows the ACTIVE TAB, so a background
# LIVE tab is not what the taskbar shows. The launchers set a title anyway.
#
# 25 is chosen to be under a default 30-row window, so at least one reminder is
# on screen at any moment rather than merely usually.
$IdentityReminder      = '---- ' + $RequestLogTag + $ServiceName + ' v' + $ServiceVersion + ' -- ' + $prefix + ' -- PID ' + $PID + ' ----'
$IdentityEveryRequests = 25
$requestCount          = 0

# Touch settings.json once at startup so a first run seeds it (and prints its
# "change the default password" warning) here, right under the banner, rather
# than buried in the request log the first time someone opens the app.
$null = Read-Settings

# --- Request loop -------------------------------------------------------------
# Single-threaded on purpose (same as the other NWMS bridges): GetContext
# blocks until a request arrives, we handle it start-to-finish, then wait for
# the next one. The per-request try/catch means one bad request can never
# take the whole service down -- it becomes a 500 and the loop carries on.
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Capture these before handling, in case the handler faults badly.
        $logMethod = $context.Request.HttpMethod
        $logPath   = $context.Request.Url.PathAndQuery

        $status = 500
        try {
            $status = Invoke-Request -Context $context
        }
        catch {
            # Handler blew up. Try to tell the client; if the response stream
            # is already gone (client hung up, headers already sent), just
            # swallow it -- the loop must keep running either way.
            # The detail goes to the CONSOLE, not to the client: .NET exception
            # messages carry full server paths, and this service will sit on the
            # LAN. Whoever is debugging has the window open in front of them.
            Write-Host ($RequestLogTag + 'ERROR ' + $context.Request.HttpMethod + ' ' + $context.Request.RawUrl + ' -- ' + $_.Exception.Message)
            try {
                $status = Send-Json -Context $context -StatusCode 500 -Json (New-ErrorBody 'internal error - see the qc-api console for detail')
            }
            catch {
                # Nothing more we can do for this request.
            }
        }

        $stopwatch.Stop()
        Write-RequestLog -Method $logMethod -Path $logPath -StatusCode $status -DurationMs ([int][math]::Round($stopwatch.Elapsed.TotalMilliseconds))

        # Re-assert which instance this window is, every so often. The [LABEL] on
        # each line above says LIVE or DEV; this says it again with the version,
        # address and PID, which the per-line tag has no room for.
        # This runs at top-level script scope, so a plain assignment updates the
        # variable -- it would need $script: if it ever moved inside a function.
        $requestCount = $requestCount + 1
        if (($requestCount % $IdentityEveryRequests) -eq 0) {
            Write-Host $IdentityReminder
        }
    }
}
finally {
    # Runs on Ctrl+C as well as on a clean stop: shut the listener down so
    # the port is released immediately.
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()

    # Then release the service lock. Disposing the stream is what actually frees
    # it -- and the OS would do that anyway if this process were killed outright,
    # so the lock can never be left permanently stuck. Deleting the file is only
    # tidiness, so nobody later finds a leftover and wonders who holds it.
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    }

    Write-Host ($ServiceName + ' stopped.')
}
