# current_scope test scenarios

Six throwaway Rails 8.1.3 host apps that stress-test the
[current_scope](https://github.com/davidteren/current_scope) gem (v0.3.0, resolved by
path from `~/Projects/DT/current_scope`; updated 2026-07-19 for the 0.3.0
release — pins of deliberately-changed 0.2.0 behavior were re-pinned to the
new shape, per-app comments name the issue numbers, and the #85 route rename
the shakedown caught is now CHANGELOG errata). Built 2026-07-14/15 by an automated
shakedown: each app was built and probed by an agent, findings were deduped and
adversarially re-verified against the gem source, and the survivors were filed as
GitHub issues [#19–#46](https://github.com/davidteren/current_scope/issues).

Every app: fake session auth (pick-a-user login, no passwords), Pico.css (Bootstrap in 05),
seeds, and an integration-test suite (`bin/rails test`) that pins the observed behavior —
including the surprising behavior, so the traps stay reproducible.

## The apps

| App | Scenario | Highlights |
|---|---|---|
| `01_baseline_blog` | README quickstart, RESTful CRUD, defaults | fail-closed baseline, `scope_for`, grant rake task, audit probes; scoped-index trap (#19) |
| `02_custom_actions` | Non-RESTful member/collection actions, wizard controller | 9 custom actions in grid, `match via: [:get,:post]`, SoD × custom action, rescue-order trap (#24) |
| `03_god_controller` | Legacy god controller (27 actions), retrofit story | big-bang 403 wall → report-only mode proposal (#37), grid at scale (#38), skip-inheritance fail-open (#26) |
| `04_sod_matrix` | Every SoD knob | veto vs full_access, missing/nil hooks, break-glass matrix, bypass_sod ungrantable (#21), impersonation × sod_identity |
| `05_legacy_ui_overrides` | Existing-UI app, namespacing, engine theming | key-derivation foot-gun live repro, `--cs-*` retheme + layout shadowing (works, undocumented → #31), custom mount path |
| `06_api_and_edge` | ActionController::API, GatingTripwire, routing edges | token auth through the gate, phantom permissions (#43), CurrentAttributes isolation, OPTIONS/mutation-guard |

## Outcome

- **45 verified findings** → consolidated into **28 issues**: 5 bugs, 13 docs, 10 enhancements
  (incl. migration tooling #45 and DX skills #46).
- All six apps end green: `cd <app> && bin/rails test`.
- Top bugs: scoped-only grants can't pass collection gates (#19), `permission_keys=`
  silent drop (#20), `bypass_sod` ungrantable via UI (#21).

Findings detail: each app has probe tests under `test/integration/`; some apps also carry a
`FINDINGS.md`. Full machine-readable finding set + issue bodies were generated in the session
scratchpad (`gen_issues.py`).

## Planned: front-end integration scenarios (engine issues [#96](https://github.com/davidteren/current_scope/issues/96), [#97](https://github.com/davidteren/current_scope/issues/97))

Two more apps are planned, covering the "separate front-end" story — how a host
passes the signed-in subject's scope (allowed keys, scoped types + ids) to a
JS front-end while the server-side gate stays authoritative:

| App | Scenario | Engine issue |
|---|---|---|
| `07_react_api` | Rails API backend + React/Next.js front-end; abilities payload over JSON; `X-Current-Scope-Reason` as the client's denial contract | #96 |
| `08_inertia` | Rails + Inertia.js (React or Vue); the same abilities payload via `inertia_share`; per-page `allowed_to?` props | #97 |

**Branch matrix** — unlike apps 01–06 (single-branch behavior pins), each
front-end scenario carries three branches so the migration itself is a
documented, reproducible example:

| Branch | Shows |
|---|---|
| `NN-raw` | the app working WITHOUT current_scope — the starting point |
| `NN-migration` | the adoption, step by step (each commit is one migration step, readable as a tutorial) |
| `main` | the finished integration, suite green, doubling as the docs' living example |

The docs guides in the engine repo ("Using CurrentScope with a separate
front-end", "CurrentScope with Inertia") will link to these branches rather
than embedding stale sample code.
