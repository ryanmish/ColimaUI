# Next Work Item: Quit Behavior and App Presence

## Goal

Define explicit, user-controlled behavior for what happens when ColimaUI quits, and how the app presents in Dock vs menu bar.

## Why this is next

Developers have different expectations:
- Some expect quitting ColimaUI to leave Colima VMs and containers running.
- Some expect quitting ColimaUI to stop Colima runtime.
- Some want menu-bar-only mode, others want normal Dock presence.

Autopilot is now implemented; this is the next major UX/system behavior decision.

## Current behavior (as of this file)

- ColimaUI-owned background services (local domains autopilot event monitor + periodic tasks) stop on app quit.
- Colima runtime is not automatically stopped on app quit.

## Proposed settings

1. `On Quit` behavior
- `Keep Colima running` (recommended default)
- `Stop active Colima profile`
- `Ask every time`

2. `App Presence`
- `Show in Dock and menu bar` (default)
- `Menu bar only`

## Implementation outline

1. Add persistent settings keys:
- `quitBehavior` (`keepRunning`, `stopColima`, `ask`)
- `menuBarOnlyMode` (`true/false`)

2. Add quit handler flow:
- Intercept quit request.
- Apply selected `quitBehavior`.
- Always stop ColimaUI-owned background services before final termination.

3. Add UI controls in Settings:
- New section: `App Behavior`.
- Include explanatory copy so behavior is predictable.

4. Add migration/default strategy:
- Existing users default to `keepRunning`.
- No surprise runtime stop after upgrade.

## Acceptance criteria

- Quitting ColimaUI always stops ColimaUI-owned background services.
- Quit behavior for Colima runtime follows user setting exactly.
- Menu-bar-only mode can hide Dock icon while retaining access.
- Behavior is documented in README and workflow docs.
