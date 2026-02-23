# Local Development Workflow

This document explains the new local-domain workflow in ColimaUI.

## What Changes

Before:
- You remember many localhost ports (`localhost:3000`, `localhost:8080`, `localhost:5173`).
- Frontend and backend URLs vary by project.

After:
- You use stable domains (`web.myapp.dev.local`, `api.myapp.dev.local`).
- ColimaUI autopilot keeps DNS, resolver, proxy, and TLS aligned.
- You can open a live domain index at `index.dev.local`.

## One-Time Setup

1. Open `Settings -> Local Domains`.
2. Enable Local Domains.
3. Suffix is fixed to `.dev.local`.
4. Wait for autopilot to reach `Healthy` (or click `Repair now` once).
5. If needed, open `Advanced Tools` to inspect detailed checks.

Notes:
- macOS can prompt for admin credentials to configure resolver and service-level networking.
- The app automatically starts a managed proxy container (`colimaui-proxy`) for domain routing.

## Daily Workflow

1. Start your stack (`docker compose up -d`).
2. Autopilot should sync routes automatically.
3. List live service URLs (`colimaui domains urls`).
4. If needed, force route sync (`colimaui domains sync`).
5. Use `index.dev.local` to inspect live routes and proxy status.

For most web services, no localhost port memorization is needed.

## Domain Rules

Generated domains:
1. Compose style: `service.project.dev.local`
2. Container fallback: `container-name.dev.local`
3. Custom labels: `dev.colimaui.domains=api.dev.local,docs.dev.local`
4. Custom wildcard labels: `dev.colimaui.domains=*.preview.dev.local`

Wildcard behavior:
- Generated domains also accept subdomains (`*.service.project.dev.local`).
- Custom wildcard labels route all matching subdomains.

## Optional Labels

Use these labels when you need control:

```yaml
services:
  api:
    image: my-api
    labels:
      - dev.colimaui.domains=api.myapp.dev.local,docs.myapp.dev.local
      - dev.colimaui.http-port=8080
```

- `dev.colimaui.domains`: Adds explicit hostnames.
- `dev.colimaui.http-port`: Overrides auto-detected HTTP port when a container exposes multiple servers.

## Frontend + Backend Example

```yaml
services:
  web:
    image: my-web
    labels:
      - dev.colimaui.http-port=3000

  api:
    image: my-api
    labels:
      - dev.colimaui.http-port=8080

  db:
    image: postgres:16
```

Result:
- `web.<project>.dev.local` routes to frontend
- `api.<project>.dev.local` routes to backend
- DB remains a direct host:port protocol (for example `db.<project>.dev.local:5432` if published)

## Troubleshooting

In `Settings -> Local Domains`, verify:
- Homebrew
- dnsmasq installed/running
- wildcard DNS line configured
- `/etc/resolver/dev.local` configured
- wildcard resolution works
- proxy is running
- mkcert installed
- TLS certificate exists
- `Domain index` passes (proxy/routing path is reachable)
- `TLS trust` passes (certificate chain is trusted by macOS tools/browsers)

If one check fails, fix that check first.

## Agent Memory

For AI assistants and automation agents, copy the snippet in:

- `docs/agent-memory-snippet.md`

You can also copy this directly from the app in `Settings -> Agent Context -> Copy Context` and paste into `AGENTS.md` or `CLAUDE.md` (Claude Code).
