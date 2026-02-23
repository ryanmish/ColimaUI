# Agent Memory Snippet (ColimaUI Local Domains)

Paste this into `AGENTS.md` or `CLAUDE.md` (Claude Code) so agents follow the current ColimaUI local-domain workflow.

```md
## ColimaUI Local Domains Context
ColimaUI is a macOS app for managing Colima VMs and Docker containers. Colima runs containers; ColimaUI adds route discovery and stable `.dev.local` local domains.

### Non-negotiables
- Domain suffix is fixed to `.dev.local`.
- Keep Local Domains Autopilot enabled in ColimaUI.
- Prefer domain URLs over localhost ports for web services.
- Index URL: `https://index.dev.local`

### Standard Workflow
1. Start services from the project root: `docker compose up -d`
2. Wait for autopilot to sync routes.
3. List live URLs: `colimaui domains urls`
4. If routes are stale: `colimaui domains sync`
5. If health/setup fails: `colimaui domains setup && colimaui domains check`

### Domain Patterns
- Compose service: `<service>.<project>.dev.local`
- Container fallback: `<container-name>.dev.local`
- Optional explicit domains label: `dev.colimaui.domains=foo.dev.local,bar.dev.local`
- Optional HTTP port label: `dev.colimaui.http-port=8080`

### Recovery
- Rebuild and verify routing: `colimaui domains setup && colimaui domains check`
- Remove local-domain setup: `colimaui domains unsetup`
- macOS can request admin permission for resolver/network/trust changes.
```
