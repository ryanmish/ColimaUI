# Local Development Workflow

This document explains the new local-domain workflow in ColimaUI.

## What Changes

Before:
- You remember many localhost ports (`localhost:3000`, `localhost:8080`, `localhost:5173`).
- Frontend and backend URLs vary by project.

After:
- You use stable domains (`web.myapp.colima`, `api.myapp.colima`).
- ColimaUI automatically configures DNS, resolver, reverse proxy, and TLS.
- You can open a live domain index at `index.<suffix>`.

## One-Time Setup

1. Open `Settings -> Local Domains`.
2. Enable Local Domains.
3. Keep the default suffix `.local` or set your own (for example `.mish`).
4. Click `One-Click Setup`.
5. Wait for all setup checks to become healthy.

Notes:
- macOS can prompt for admin credentials to configure resolver and service-level networking.
- The app automatically starts a managed proxy container (`colimaui-proxy`) for domain routing.

## Daily Workflow

1. Start your stack (`docker compose up`).
2. Open service domains from ColimaUI container rows/details.
3. Use `index.<suffix>` to inspect live routes and proxy status.

For most web services, no localhost port memorization is needed.

## Domain Rules

Generated domains:
1. Compose style: `service.project.<suffix>`
2. Container fallback: `container-name.<suffix>`
3. Custom labels: `dev.colimaui.domains=api.mish,docs.mish`
4. Custom wildcard labels: `dev.colimaui.domains=*.preview.mish`

Wildcard behavior:
- Generated domains also accept subdomains (`*.service.project.<suffix>`).
- Custom wildcard labels route all matching subdomains.

## Optional Labels

Use these labels when you need control:

```yaml
services:
  api:
    image: my-api
    labels:
      - dev.colimaui.domains=api.myapp.mish,docs.myapp.mish
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
- `web.<project>.<suffix>` routes to frontend
- `api.<project>.<suffix>` routes to backend
- DB remains a direct host:port protocol (for example `db.<project>.<suffix>:5432` if published)

## Troubleshooting

In `Settings -> Local Domains`, verify:
- Homebrew
- dnsmasq installed/running
- wildcard DNS line configured
- `/etc/resolver/<suffix>` configured
- wildcard resolution works
- proxy is running
- mkcert installed
- TLS certificate exists
- `https://index.<suffix>` is reachable

If one check fails, fix that check first.

## Agent Memory

For AI assistants and automation agents, copy the snippet in:

- `docs/agent-memory-snippet.md`

You can also copy this directly from the app in `Settings -> Docs + Agent Copy Pack -> Copy Agent Snippet`.
