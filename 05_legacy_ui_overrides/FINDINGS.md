# FINDINGS — 05_legacy_ui_overrides (current_scope v0.2.0)

Scenario: existing-UI app (Bootstrap 5, own design system), namespaced duplicate
controllers, engine mounted at a custom path (`/permissions`),
`parent_controller = "Admin::BaseController"`, custom `permission_grid_groups`,
`subject_label` probes, `excluded_controllers` probes, branded host 403.

Environment: ruby 3.4.9, Rails 8.1.3, gem via `path:`. All 26 integration tests
green at end state. Probe scripts: `test/probes/*.rb` (run with
`RAILS_ENV=test bin/rails runner ...`).

Build papercut (recipe, not the gem): `rails new 05_legacy_ui_overrides` fails —
"Invalid application name ... does not start with numbers". Generated as
`legacy_ui_overrides` and renamed the directory.

---

## F1 (major, docs) — No theming/overrides documentation and no views generator, although the mechanisms exist and work

**What I did:** Integrated the engine UI into an app with its own design system
(Bootstrap 5). Read the gem's `app/` to find the actual mechanism, then
rethemed by creating `app/views/layouts/current_scope/application.html.erb` in
the host.

**Actual mechanism (all verified):**
- Engine layout is declared explicitly (`layout "current_scope/application"` in
  `CurrentScope::ApplicationController`), so it never inherits the
  `parent_controller`'s layout (good — see F9).
- Standard Rails view-path precedence means a host file at
  `app/views/layouts/current_scope/application.html.erb` (or any
  `app/views/current_scope/**`) shadows the engine's copy. My Bootstrap
  override rendered on first try (test: "host retheme ... shadows the engine
  layout").
- The engine CSS is genuinely theme-ready: ~197 uses of `--cs-*` custom
  properties, token defaults wrapped in `@layer current_scope.tokens` explicitly
  so "a host's own (unlayered) :root override always wins". Retheme-by-CSS-vars
  is *designed in*.

**The problem:** every word of that is documented ONLY in a comment at the top
of `app/assets/stylesheets/current_scope/application.css`. The README has zero
occurrences of "layout", "theme(ing)", "override" (in the UI sense), or view
override paths. And `lib/generators/current_scope/` contains only `install` —
there is no `current_scope:views` / `current_scope:theme` generator.

**How much it hurts:** a host developer has to read the gem source to learn (a)
the override file path, (b) that the layout must re-include
`stylesheet_link_tag "current_scope/application"` and the engine JS or the
views degrade to unstyled `cs-*` soup, (c) that flash rendering, the theme
toggle, and the "full access" badge are the layout's job and vanish with it,
(d) that `main_app.` is needed for host links.

**Proposal:** a `current_scope:views` generator (devise-style) that copies the
engine layout (and optionally the views) into the host, plus a README
"Theming & overrides" section: CSS-token override snippet (the `@layer` trick
is a genuinely good story — tell it!), layout override path, view override
paths.

**Known/documented?** No — undocumented in README; partially documented in a
CSS source comment.

## F2 (major, docs/dx) — Out-of-the-box denial is a blank 403 page; the rescue is silently installed and override is declaration-order-sensitive

**What I did:** Followed the README install (Context + Guard, no rescue_from),
then made a no-grant request. Probe C (`excluded_and_defaults_probe.rb`):

```
[default denial] GET /dashboard -> HTTP 403
[default denial] body: "" (0 bytes)
[default denial] X-Current-Scope-Reason: "no_grant"
```

**Expected (from README):** "Denials raise CurrentScope::AccessDenied" — I
expected either a 500 (unrescued) or documented guidance to rescue. Actually
`MutationGuard` (pulled in by `include Guard`) silently installs
`rescue_from CurrentScope::AccessDenied` -> `head :forbidden`. So the status is
right (403, not 500 — good) but the UX is a **completely blank white page**,
and the README never mentions:
- that including Guard installs a rescue_from on your ApplicationController
  (hidden side effect of an include — least-astonishment violation);
- how to brand the page. The working host pattern (verified green):

  ```ruby
  # AFTER include CurrentScope::Guard — order matters!
  rescue_from CurrentScope::AccessDenied do |e|
    @permission, @reason = e.message, e.reason
    render "errors/forbidden", status: :forbidden
  end
  ```

  A host that declares its `rescue_from` *above* the includes silently keeps
  getting the blank page (later-declared handler wins in Rails). Nothing warns.

**Proposal:** README section "Rendering denials" with the pattern above and an
explicit note on ordering; mention the built-in blank-403 default.

**Known/documented?** No. README documents the exception and header, not the
default response or the branding recipe.

## F3 (minor, enhancement) — AccessDenied exposes enough for a basic 403 page, but the permission rides in #message and there's no record/subject

**What I did:** Built the branded Bootstrap 403 (probe 9). Available:
`#reason` (`:no_grant` / `:sod_veto` / `:impersonation_gate`) and the
permission key — but only as `#message`. Rendering `e.message` as "the
permission" works today yet is fragile API (a message is prose, not data;
nothing stops a future version prepending text). There is no `#permission`
attribute, and no `#record` / `#subject` for pages like "ask the owner of
Report #7 for access" or for audit-friendly logging in the host's handler.

**Proposal:** `AccessDenied#permission` (dedicated attr), optionally
`#record`/`#subject` (Guard has both in hand when raising).

**Known/documented?** Not discussed anywhere.

## F4 (minor, enhancement) — No `rescue_responses` registration: an escaped AccessDenied is a 500

Probe D: `ActionDispatch::ExceptionWrapper.rescue_responses["CurrentScope::AccessDenied"]
= :internal_server_error`. Inside Guard'd controllers MutationGuard's
rescue_from catches it, but an `AccessDenied` raised anywhere else (a PORO
using `CurrentScope::Permissions` that raises on deny, a controller that
includes only Context, custom code re-raising) becomes a production 500.
One engine line fixes it:
`config.action_dispatch.rescue_responses["CurrentScope::AccessDenied"] = :forbidden`.

**Known/documented?** No.

## F5 (confirmation + enhancement, minor) — The documented key-derivation foot-gun reproduces EXACTLY as the README describes; the gem could plausibly warn

**What I did (probe 2):** DashboardController (path `dashboard`, renders
`Report`s, route key `reports`).

- *Link shows but 403s* (verified): user granted `reports#index reports#show`
  only. Reports view guards a Dashboard link with `allowed_to?(:show, report)`
  -> derives `reports#show` -> true -> link renders; click -> gate enforces
  `dashboard#show` -> 403 `no_grant`.
- *Hide that would work* (verified): user granted `dashboard#show` only, ON the
  dashboard the gate just passed, but a widget guarded by
  `allowed_to?(:show, report)` (derives `reports#show`) disappears.
- *Prescribed fix* (verified): `allowed_to?("dashboard#show")` agrees with the
  gate in both directions.
- *Guard authoritative* (verified): display bug only, no bypass.

**Known/documented?** YES — this is the README's "Residual foot-gun" callout,
and behavior matches the docs exactly. Credit where due.

**Enhancement:** the gem can detect the ambiguity at check time: in
`CurrentScope.permission_key`, when a bare action + record are given, a
`controller_path` is present, and `controller_path.split("/").last !=
record.model_name.route_key`, the short form silently ignores the current
controller. That exact condition is the foot-gun. A dev/test-only nudge
(mirroring `warn_on_nil_sod_record`), e.g.
`config.warn_on_cross_controller_derivation`, logging
"`allowed_to?(:show, Report)` inside `dashboard` derived `reports#show`, not
`dashboard#show` — pass the full key if you meant the gate's permission" would
catch it in development.

## F6 (minor, dx) — Advisory checks never consult the catalog: uncataloged keys are silently false — or silently TRUE if a stale grant row exists

**What I did (probe 3):**
- Inside `Admin::ReportsController` views, `allowed_to?(:approve, report)`
  resolves to `admin/reports#approve` via the path-suffix rule — verified
  (button renders for the granted role; POST approves; hides + 403 without the
  grant). Matches README.
- From a top-level reports view, the same call derives `reports#approve` —
  unrouted, not in the catalog. Result: **silently false**. No log, no raise —
  even though the subject actually holds `admin/reports#approve`. Asymmetric
  with the Guard, which raises a loud ConfigurationError for uncataloged gate
  keys.
- Worse: after inserting a grant row directly
  (`RolePermission.create!(permission_key: "reports#approve")` — the UI can't
  create it, but seeds/console can), `allowed_to?(:approve, report)` returns
  **true** for a permission that no route enforces and the grid can't display.

**Expected:** advisory checks and enforcement to share the catalog's notion of
"this key exists", or at least a dev-mode signal on uncataloged advisory keys —
a typo'd `allowed_to?("reprots#show")` is indistinguishable from a real deny.

**Known/documented?** No. Fail-closed, so not a security hole, but a real
debugging wall.

## F7 (minor, dx) — `Role#permission_keys=` silently drops unknown keys: a typo'd seed no-ops with zero signal

> **2026-07-19, 0.3.0: fixed by #20** — unknown keys now fail validation loudly;
> `assign_permission_keys(..., scrub: true)` is the deliberate opt-in to dropping.
> See test "permission_keys= rejects uncataloged keys loudly" in
> `test/integration/namespaced_permissions_test.rb`.

Verified: `role.update!(permission_keys: %w[report#show reports#approve
reports#index])` persists only `["reports#index"]`. The singular/typo key and
the unrouted key vanish silently. In seeds/bootstrap scripts this turns into
"why is everyone 403ing" with nothing in the logs. The filtering is deliberate
(stale keys from removed controllers must drop on grid saves) but a
programmatic writer deserves a signal.

**Proposal:** log dropped keys, or add a bang/strict variant for seeds.
**Known/documented?** The dropping is mentioned in the model's source comment
only; not in README, and there's no runtime signal.

## F8 (minor, ux) — Grid: `reports` vs `admin/reports` are distinguishable but scattered; nothing links two rows over the SAME model

Grid rows (probe output): `admin/reports, dashboard, reports, sessions` —
plain-text controller paths, alphabetical. Independence of the two permission
sets is fully enforced (verified both directions: a `reports#index` grant does
not open `/admin/reports` and vice versa; each denial 403s with `no_grant`).
Presentation gripes for a real app:
- Alphabetical sort scatters namespaces: `admin/reports` sits at the top,
  `reports` two rows down; with 30 controllers and 4 namespaces related rows
  are far apart. No grouping, indent, or namespace header.
- Nothing indicates both rows CRUD the same `Report` model — an admin ticking
  "reports destroy" may believe they covered the admin surface too.

**Known/documented?** Not discussed. Suggest namespace grouping (sort by
namespace, visually indent) as a cheap fix.

## F9 (confirmation, works) — `parent_controller = "Admin::BaseController"`: host auth composes correctly; engine keeps its own layout

Verified:
- Host `require_admin!` runs before the engine's `require_full_access!`: a
  full-access subject WITHOUT the host admin flag gets the host's "Admins only"
  403. Host auth genuinely gates the engine.
- A host-admin without full access gets `head :forbidden` from the engine.
- `layout "admin"` on `Admin::BaseController` is NOT inherited by the engine
  (explicit `layout "current_scope/application"` wins) — no ADMIN-LAYOUT-MARKER
  in engine pages, before and after my override. Predictable and good.
- The host's branded `rescue_from AccessDenied` is inherited by engine
  controllers via the parent chain — harmless here (engine uses
  `head :forbidden` directly, it doesn't raise), but worth a docs sentence.

## F10 (papercut, ux) — The engine's own 403 (`require_full_access!`) is a naked blank page with no reason

> **2026-07-19, 0.3.0: fixed by #23** — `require_full_access!` now raises
> `AccessDenied(:not_full_access)`: reason header present, explanatory page
> rendered (here, the host's inherited branded 403 — F9's rescue_from note is
> now load-bearing). See test "host admin without full access gets a reasoned
> 403" in `test/integration/engine_ui_test.rb`.

A host-admin who lacks full access gets `head :forbidden`: 0-byte body, and —
unlike Guard denials — **no `X-Current-Scope-Reason` header**. For the one page
an admin will be sent to ("manage roles here"), a blank white page is a
dead-end (no "you need a full-access role", no way back). Papercut, but it's
the first impression of the product.

## F11 (major, docs) — `excluded_controllers`: the loud error is excellent, but "excluded means UNPROTECTED once you skip" is not stated loudly enough

**Probe A (exclude while still gated)** — exact behavior as promised, great
error:

```
CurrentScope::ConfigurationError: "admin/reports#index" is not in the permission
catalog (excluded_controllers or not routed). Either stop excluding it, or skip
the gate here with skip_before_action :current_scope_check!.
```

**Probe B (exclude + skip, the "proper" fix per the error message):**
- Grid: `admin/reports` rows gone (verified).
- A host-admin with **zero** CurrentScope grants: `GET /admin/reports` -> 200,
  `POST .../approve` -> 302, report actually approved. The whole namespace is
  now gated by NOTHING from CurrentScope — in this app only the host's own
  `require_admin!` flag stood in the way; a host without its own check would be
  serving these actions to any signed-in user.

**The gap:** the error message *recommends* `skip_before_action` without noting
the consequence; README's coverage is "keep infrastructure out of the grid";
the initializer comment says excluded controllers "must also skip the gate" —
none of the three says **"excluded + skipped = this controller is no longer
protected by CurrentScope at all; bring your own auth"**. For an authorization
gem, that sentence belongs in all three places.

**Known/documented?** Mechanics yes; security consequence no.

## F12 (minor, bug-ish) — `subject_label` Proc is not error-isolated: one bad subject 500s the whole subjects page; Symbol form is defensive

> **2026-07-19, 0.3.0: fixed by #22 (PR #54)** — the Proc form is now
> per-subject error-isolated with a once-per-cause warning, matching the Symbol
> form. See test "subject_label Proc that raises on one subject falls back" in
> `test/integration/engine_ui_test.rb`.

Verified (probe 6):
- `config.subject_label = :email` -> emails render; a subject with `email: nil`
  falls back to the default chain (shows the name).
- `config.subject_label = :department` (method doesn't exist) -> **silently**
  falls back for every subject (`respond_to?` check). No error — arguably too
  quiet: a typo'd symbol means your config does nothing and nothing tells you.
- `config.subject_label = ->(u) { u.email.upcase }` with one nil-email subject
  -> `ActionView::Template::Error` (cause `NoMethodError: undefined method
  'upcase' for nil`) -> the ENTIRE subjects page 500s because of one row.

The asymmetry is the surprise: Symbol is double-guarded (respond_to? +
blank-fallback), Proc is raw. A per-subject rescue -> fallback (like the
existing `current_scope_holder_subject_label` rescue pattern one method below)
would make the Proc form equally robust; alternatively document "your Proc must
be total".

**Known/documented?** No.

## F13 (minor, ux) — Overlapping `permission_grid_groups` render one permission as two independent-looking checkboxes; no validation warns

Config: `"read" => %w[index show], "workflow" => %w[approve show]` (`show` in
two groups). Verified on the `dashboard` row (routes only `show`):
- Both the read and workflow cells render checkboxes for the SAME single key
  `dashboard#show`; grant it and **both render checked**.
- Save with only `dashboard:read` ticked -> key granted -> re-render shows
  `dashboard:workflow` checked too, though nobody ticked it. Unticking
  workflow while read stays ticked revokes nothing.
- Also misleading label semantics: `reports:workflow` (reports routes no
  `approve`) grants... `reports#show` — a "workflow" tick that actually grants
  read access.

Cell *alignment* held everywhere (blank cells, no shifted columns — probe
output below), exactly as documented. With default groups, `approve` becomes
its own raw-key leftover column, blank for every controller but
`admin/reports` — also as documented.

```
columns: ["Controller", "read", "create", "update", "destroy", "workflow"]
  admin/reports  [read, create, update, destroy, workflow]
  dashboard      [read, ., ., ., workflow]      <- both cells = dashboard#show
  reports        [read, create, update, destroy, workflow]  <- workflow = show only
  sessions       [read, create, ., destroy, .]
```

**Proposal:** validate `permission_grid_groups` for overlapping actions at boot
(ConfigurationError or warn), since the grid's own escalation-guard logic
(partial groups) shows the design cares about grid truthfulness.

**Known/documented?** Overlap behavior undocumented.

## F14 (papercut, ux) — Gate-skipped controllers still occupy the grid as grantable no-ops

> **2026-07-19, 0.3.0: addressed by #62** — provably ungated rows (sessions
> here) now carry a "gate not run" badge in the grid; cells stay tickable by
> design. `bin/rails current_scope:ungated` lists the same inventory.

`SessionsController` skips the gate (per README), yet the grid offers
`sessions:read/create/destroy` checkboxes. Ticking them changes nothing — the
gate never runs there. In a real app every public/webhook/health controller
that follows the README's skip pattern becomes grid noise, and an admin can
"grant" permissions that do nothing. The only cleanup is
`excluded_controllers` (fine for skipped controllers), but nothing suggests
that pairing, and F11's caveat applies.

## F15 (confirmation, works) — Custom mount path `/permissions` is flawless; no hardcoded `/current_scope` anywhere

All engine pages (roles/subjects/events, edit grids, forms, pagination) render
and submit under `/permissions`. Scanned every fetched page for
`href="/current_scope` / `action="/current_scope`: zero hits (the only
`/current_scope` substrings are asset digests under `/assets/current_scope/...`,
which are mount-independent). Route helpers are used consistently throughout.

## F16 (papercut, fit-and-finish) — Running the engine UI inside a real product

- Stock engine chrome has **no link back to the host app** (verified: no
  `href="/"` in stock layout) — it's a cul-de-sac; users use the browser back
  button.
- Overriding the layout (the only retheme path, F1) silently drops: flash
  rendering, the dark-mode toggle + `current_scope_theme` cookie handling, and
  the "full access" badge — all live in the layout. My override had to
  re-implement flash manually.
- The hardcoded "full access" topbar badge and "CurrentScope" branding aren't
  configurable (product name in an admin tool ideally follows the host).
- Grid page inside a Bootstrap host: the `cs-*` styles are fully self-contained
  and didn't clash with Bootstrap in either direction (good — everything is
  namespaced).

---

## Scenario checklist

| # | Probe | Result |
|---|---|---|
| 1 | namespaced duplicate independence | enforced both ways (tests); grid presentation -> F8 |
| 2 | key-derivation foot-gun | reproduces exactly per README; fix works; warn idea -> F5 |
| 3 | approve resolution admin vs top-level | suffix match works; uncataloged key silently false/true -> F6 |
| 4 | custom mount path | clean -> F15 |
| 5 | parent_controller + layout + retheme | works -> F9; docs/generator gap -> F1 |
| 6 | subject_label Symbol/Proc | Symbol robust, Proc 500s -> F12 |
| 7 | excluded_controllers | loud error verbatim; exclude+skip = unprotected -> F11 |
| 8 | grid group collisions | aligned, but overlap mispresents -> F13 |
| 9 | branded 403 | works; default blank 403 + API gaps -> F2, F3, F4 |
| 10 | fit-and-finish | -> F10, F14, F16 |
