# STATUS — the current_scope validation fleet

> Last updated: 2026-07-19.
> This file is the repo's worklist and source of truth. An agent asked to
> "work on the scenarios" starts HERE, picks the next unblocked task, and
> updates this file (and the linked issue) when done.

## What this repo is

One repository holding **many independent Rails host apps** ("scenarios") that
validate the [current_scope](https://github.com/davidteren/current_scope)
authorization engine from the outside — the way real adopters meet it. It is
not one application: each `NN_*/` directory is a self-contained Rails app with
its own Gemfile, suite, and purpose. The fleet exists to:

1. **Pin behavior** — including surprising behavior — so engine changes that
   alter host-visible semantics are caught here (the 0.2.0 shakedown filed
   engine issues #19–#46; the 0.3.0 update pass caught the undocumented #85
   route rename).
2. **Prove integrations** — separate front-ends, Inertia — against a written
   contract, on a reproducible branch matrix.
3. **Exercise migrations** — apps starting on Action Policy / Pundit /
   CanCanCan, migrated to current_scope with agentic assistance, with parity
   proven, feeding the engine's migration tooling
   ([engine #45](https://github.com/davidteren/current_scope/issues/45)).
4. **Self-evaluate** — score its own scenarios and route findings to the right
   backlog: engine defects → engine issues; harness weaknesses → issues here.

## Task list (ordered; each links its issue)

| # | Task | Issue | Status |
|---|---|---|---|
| 0 | **AGENTS.md + CLAUDE.md** — the repo's contract, so any agent understands the fleet before touching it. Everything below assumes it. | [#1](https://github.com/davidteren/current_scope_test_scenarios/issues/1) | ☐ todo |
| 1 | **Per-app READMEs for 01–06** — what it is / what it validates / how it tests, per the contract below. | [#2](https://github.com/davidteren/current_scope_test_scenarios/issues/2) | ☐ todo |
| 2 | **Dev runner** — `bin/scenario` + Overmind/Procfile.dev; auto-picks the next free port (maintainer runs other apps locally); `up`, `test`, `test --all`, `branches`, `eval` subcommands. | [#3](https://github.com/davidteren/current_scope_test_scenarios/issues/3) | ☐ todo |
| 3 | **Dev containers for every app** — shared base definition, Node only where needed, suite green inside the container. | [#4](https://github.com/davidteren/current_scope_test_scenarios/issues/4) | ☐ todo |
| 4 | **Build `07_react_api`** — Rails API + React/Next.js on the branch matrix; proving ground for [engine #96](https://github.com/davidteren/current_scope/issues/96) (abilities payload). | [#5](https://github.com/davidteren/current_scope_test_scenarios/issues/5) | ☐ todo |
| 5 | **Build `08_inertia`** — Rails + Inertia on the branch matrix; proving ground for [engine #97](https://github.com/davidteren/current_scope/issues/97). Depends on 07 settling the payload shape. | [#6](https://github.com/davidteren/current_scope_test_scenarios/issues/6) | ☐ todo |
| 6 | **Migration-source scenarios** — `09_action_policy`, `10_pundit`, `11_cancancan`: incumbent-library apps migrated to current_scope with agentic assistance + parity proof. Action Policy first (per [engine #45](https://github.com/davidteren/current_scope/issues/45)'s recorded decision). | [#7](https://github.com/davidteren/current_scope_test_scenarios/issues/7) | ☐ todo |
| 7 | **Self-evaluation harness** — per-scenario EVAL.md scorecards, `bin/scenario eval`, and the feedback rule (engine defect → engine issue with repro; harness gap → issue here). The migration prompts/skills live in this repo and are themselves under test. | [#8](https://github.com/davidteren/current_scope_test_scenarios/issues/8) | ☐ todo |

Sequencing: 0 → 1 can go immediately and in parallel with 2 → 3. The builds
(4, 5, 6) want the runner and containers first so every new app lands on the
conventions. 7 grows alongside the builds rather than after them.

## The fleet

**Existing (single-branch behavior pins, all green on engine 0.3.0):**
`01_baseline_blog` · `02_custom_actions` · `03_god_controller` ·
`04_sod_matrix` · `05_legacy_ui_overrides` · `06_api_and_edge` — see the
[README](README.md) table for what each covers.

**Planned:**

| App | Kind | Engine issue |
|---|---|---|
| `07_react_api` | separate front-end (Rails API + React/Next.js) | [#96](https://github.com/davidteren/current_scope/issues/96) |
| `08_inertia` | Inertia.js (React or Vue) | [#97](https://github.com/davidteren/current_scope/issues/97) |
| `09_action_policy` | migration source: Action Policy | [#45](https://github.com/davidteren/current_scope/issues/45) |
| `10_pundit` | migration source: Pundit | [#45](https://github.com/davidteren/current_scope/issues/45) |
| `11_cancancan` | migration source: CanCanCan | [#45](https://github.com/davidteren/current_scope/issues/45) |

## The branch matrix (front-end and migration scenarios)

| Branch | Shows |
|---|---|
| `NN-raw` | the app working WITHOUT current_scope — greenfield-minus-authz for 07/08; on its incumbent library with normal policies for 09–11. Suite green. |
| `NN-migration` | the adoption/migration executed step by step — **each commit is one step**, readable as a tutorial; for 09–11 the steps are driven by the repo's migration prompts/skills so the agentic flow itself is reproducible. |
| `main` | the finished integration: suite green, README + EVAL.md current; for 09–11 additionally a **parity check** proving incumbent answers == current_scope answers across a subject × grant matrix. |

Apps 01–06 stay single-branch — they pin behavior, they don't demonstrate
adoption.

## Per-app README contract

Every app directory carries a README with exactly this shape:

1. **Purpose** — what this app is, in 2–3 sentences a newcomer can follow.
2. **What it validates** — bullets, each mapped to the engine issue/behavior
   it guards.
3. **How it tests** — which suites/probes, the notable traps, anything
   order-dependent or deliberately surprising.
4. **How to run** — defer to `bin/scenario`; note extra processes (Node,
   etc.) and the branch matrix if the app has one.

## Dev experience requirements

- **One command up:** `bin/scenario up NN` — Overmind + per-app Procfile.dev;
  automatically selects the next available port and prints it loudly (the
  maintainer tests other apps locally; never assume 3000 is free).
- **Dev containers:** every app runs green inside its devcontainer; Codespaces
  and cloud agents are first-class.
- **Branch testing is easy:** `bin/scenario branches NN` lists/switches the
  matrix; `bin/scenario test NN` runs one suite; `--all` sweeps the fleet.

## Self-evaluation & feedback (the loop that makes this a fleet)

- Each scenario keeps an **EVAL.md scorecard**: the claims it validates, the
  test verifying each, and the last run's result. `bin/scenario eval`
  refreshes them.
- **Feedback rule:** a finding about *engine behavior* is adversarially
  verified against engine source, then filed on
  [davidteren/current_scope](https://github.com/davidteren/current_scope/issues)
  with the repro test. A finding about *our own testing* (weak pin, missing
  probe, flaky harness) is filed here. Nothing gets silently patched around.
- The **migration prompts/skills** (for task 6) live in this repo — when an
  eval exposes a gap, the fix lands in the tooling, not just the app, so the
  next migration run starts smarter.
