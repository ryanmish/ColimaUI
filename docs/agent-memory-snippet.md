# Agent Memory Snippet (ColimaUI Local Domains)

Paste this into `AGENTS.md` or `cloud.md` so agents always use ColimaUI local domains correctly.

```md
## ColimaUI Local Domains
- Domain suffix: `.local` (replace if your team uses another suffix like `.mish`)
- Index URL: `https://index.local`

### Required Agent Workflow
- Before testing local services, run: `colimaui domains check --suffix local`
- If checks fail, run: `colimaui domains setup --suffix local`, then run check again.
- After starting/stopping containers, run: `colimaui domains sync --suffix local`.
- Prefer domain URLs over localhost ports for browser-based testing.

### Domain Rules
- Compose service domain: `<service>.<project>.local`
- Container fallback domain: `<container-name>.local`
- Custom domains label: `dev.colimaui.domains=foo.local,bar.local`
- Custom port label: `dev.colimaui.http-port=8080`

### Troubleshooting
- If `dnsmasq service` fails, run setup again and accept the macOS admin prompt.
- If TLS/index fails, re-run setup and then check.
- To remove all local-domain setup: `colimaui domains unsetup --suffix local`
```
