# NWMS Quality Records — service and deployment

Internal repository for **North West Metal Sections'** quality-records system: the
API service it runs on, the scripts that deploy it to NW-APPSERVER, and the
project documentation.

> **Private repository.** These files name the internal server, its network
> shares, the default privileged password, and a customer's part number. None of
> it is a live secret — the password is a documented default that is changed on
> first setup — but it is internal infrastructure and it is not for publication.

## What is here, and what is not

| | Where |
|---|---|
| **The API service** — `qc-api.ps1`, a single-file PowerShell HTTP service | `qc-api/` |
| **Deployment scripts** — configure, publish, rollback, backup, deploy | `scripts/` |
| **Launchers** — the double-clickable `.cmd` files | repository root |
| **Documentation** — deployment plan, data model, gap analysis, changelog | repository root |
| **The web application itself** | **not here** — see below |

The front end lives in its own repository, **[haywarddh/qc](https://github.com/haywarddh/qc)**,
which syncs two-way with Lovable. It is deliberately excluded here (`.gitignore`)
because committing the same files in two places would create a second source of
truth and break that sync. Locally it sits at `qc/` beside this repository's
files, and the publisher expects to find it there.

Also excluded, and never to be committed: `qc-api/data/` (live quality records,
photographic evidence, the password hash), `qc-api/Backups/`, and `backups/`.
A record can be retyped; a photograph cannot be retaken once the parts have
shipped, and customer drawings are the customer's property.

## The shape of it

Two artefacts, always published together and carrying **one version** between
them (see `CHANGELOG.md` for the scheme and why the publisher enforces it):

```
browser ──► qc-api.ps1 ──┬──► /api/…        JSON: plans, libraries, attachments
                         └──► everything else: the built front end from web\
```

`qc-api.ps1` is both the API and the static file host, so a deployment needs
**no runtime on the server** — no Node, no IIS. Windows PowerShell 5.1 is enough,
which is why it fits alongside the Weekly Delivery Planner and Tool Room on
NW-APPSERVER and is operated the same way.

## Deploying

Read **`NWMS ISIR - Deployment Plan (NW-APPSERVER).md`** first — it covers the
one-time administrator setup, the publish loop, rollback, and the traps that have
already cost time on this estate (the Domain-profile firewall rule that silently
drops connections; http.sys reporting the listening socket as PID 4).

The short version, from a laptop:

```
npm run build            # in qc/ — the version is compiled into the bundle
Deploy to NW-APPSERVER.cmd
```

Two rules that are not negotiable:

1. **Nothing reaches Live unless it is expressly asked for.** Changes go to Dev
   (`\\NW-APPSERVER\NWMS_QC_Dev`, port 8792) for extended UAT first; Live
   (`\\NW-APPSERVER\NWMS_QC`, port 8791) follows only on request.
2. **Nothing is ever executed remotely on NW-APPSERVER.** A publish is a file
   copy to a UNC path; the service is started and stopped on the server by hand.
   There is no WinRM, PSRemoting or PsExec anywhere in this estate, and the
   laptop is deliberately non-domain to keep the blast radius small.

## Security posture, stated plainly

The app has **no user accounts**. Anyone who can reach the port can read and
write everything except the password-gated privileged actions. That is why the
firewall rule is Domain-profile and LAN-only, and why the footer says so on every
page. Do not expose it beyond the LAN without solving authentication first.
