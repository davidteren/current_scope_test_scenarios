# FINDINGS — 03_god_controller (legacy god controller, big-bang adoption)

Scenario: retrofit current_scope v0.2.0 onto a "legacy" app: one
`LegacyController` with **27 routed actions** (mixed render/redirect/JSON,
collection + `:id` routes across 3 models), fake session auth, then adopt the
gem big-bang. Rails 8.1.3 / ruby 3.4.9. All probes are integration tests
(`bin/rails test`, 28 tests green) plus `bin/rails runner` catalog dumps.

Severity legend: blocker / major / minor / papercut.

---

## F1. No monitor / log-only mode — adoption is a big-bang 403 wall (major, enhancement)

**What I did:** Built the app without the gem (baseline test green: any
signed-in user can use all 27 actions). Added the gem + `Context`/`Guard` per
README. Re-ran the baseline.

**Expected (as a legacy team):** some way to observe would-be denials before
enforcing — a `log_only`/monitor mode is the standard retrofit tool
(cf. Bullet, CSP report-only, strong_migrations safety valves).

**Actual:** every gated action returns `403 Forbidden` for **every** user
(including full sign-ins) until roles exist and are granted. Searched README
and `lib/` for `monitor|log_only|dry_run|enforce`: nothing. The only
gradual-adoption tools are `skip_before_action :current_scope_check!` (per
action, fail-open) and full_access grants (per subject, all-or-nothing).

**Evidence:** `test/integration/legacy_retrofit_test.rb` — "WALL 2" test:
stats/export_csv/import/approve_all/settings all 403 with
`X-Current-Scope-Reason: no_grant` for a signed-in roleless user.

**README documents it?** The fail-closed baseline is loudly documented ("No
grant means denied") — the wall is by design. The *absence of any migration
path other than skip* is not acknowledged anywhere.

**Concrete proposal:** `config.enforcement = :enforce (default) | :log_only`,
plus per-controller `current_scope_log_only!` for staged rollout. In
`:log_only`, `Guard` computes the decision, logs/instruments
(`current_scope.would_deny` ActiveSupport::Notification with permission key +
subject id) and allows. Teams then mine real traffic into role definitions
before flipping to `:enforce`. Bonus: the events table already exists — a
`would_deny` event stream would let the management UI *show* which roles need
which keys before enforcement day.

> **2026-07-19, 0.3.0:** F1 fixed — `config.enforcement = :report` is exactly
> the proposed monitor mode: `:no_grant` denials pass through as
> `X-Current-Scope-Reason: would_deny` + an `access.would_deny` ledger event,
> summarized by `bin/rails current_scope:report`. See the new report-mode test
> in `legacy_retrofit_test.rb`. **Retrofit caveat:** report mode downgrades
> ONLY `:no_grant` — a `model_undeclared` denial (nil record hook, no
> `current_scope_model`, subject holding a matching scoped grant, i.e. the F6
> shape) hard-403s even in report mode, so a god-controller retrofit with an
> incomplete action→model table will see real 403s during the observe phase
> (see `scoped_records_test.rb` "fail closed" test).

## F2. Guard runs before the host's own auth callback — login redirect silently breaks (major, bug/docs)

**What I did:** Followed the README install snippet exactly: the two
`include`s at the top of `ApplicationController`, which already had
`before_action :require_login` (redirects anonymous users to sign-in).

**Expected:** anonymous user hitting `/legacy/stats` is redirected to the
login page (pre-gem behavior, and what any host's auth stack promises).

**Actual:** anonymous user gets a **bare 403 with an empty body**. Guard's
`before_action :current_scope_check!` is registered at include time — i.e.
*before* the host's own `before_action :require_login` line below the
includes — so the gate fires first, `Current.user` is nil, and the resolver
denies with `:no_grant` before the auth redirect can run. Every host that has
an existing "redirect to sign-in" callback and pastes the README snippet gets
this.

**Evidence:** `legacy_retrofit_test.rb` "WALL 1": `GET /legacy/stats` (no
session) → 403, `X-Current-Scope-Reason: no_grant`. Pre-gem test asserted
`assert_redirected_to sessions_path` and passed.

**README documents it?** No. The README install section shows the includes
with no ordering guidance relative to existing host callbacks.

**Workaround:** declare the auth `before_action` *above* the includes, or
`prepend_before_action :require_login`. One README sentence would save every
retrofitting team an afternoon: "Guard registers its callback at include
time; declare any authenticate/redirect callback before the includes."

## F3. A denial is a blank white page; README never says how to customize it (minor, ux/docs)

**What I did:** Observed what an *unrescued* `CurrentScope::AccessDenied`
does to a real host.

**Actual:** it never reaches the host unrescued — `MutationGuard` (included
by `Guard`) installs `rescue_from CurrentScope::AccessDenied` →
`head :forbidden` + `X-Current-Scope-Reason` header
(`lib/current_scope/mutation_guard.rb:24,49-53`). So: correct 403, never a
500 — good. But the body is **empty**: a human gets a blank white page with
no "you don't have access" text, no way home.

**README documents it?** It documents the header and the reasons, but never
that the response body is empty, and never how to render a friendly denial
page. The supported seam appears to be overriding the private
`current_scope_denied(exception)` in `ApplicationController` — undocumented.

**Proposal:** README recipe: "override `current_scope_denied` to render your
403 page", or render a minimal default template.

## F4. Grid at god-controller scale: 32 columns, ~2.3 viewports wide, 65% blank (major, ux)

**What I did:** Fetched `/current_scope/roles/:id/edit` as a full-access
Owner in an integration test and measured the matrix
(`test/integration/grid_ui_test.rb`).

**Numbers (3 controllers: legacy, legacy_sub, sessions):**
- header columns: **32** (1 controller col + 3 CRUD group cols + **28 one-off
  action columns** — every non-CRUD legacy action gets its own column)
- rows: 3; data cells: 93; **blank cells: 60 (65%)** — the sessions and
  legacy_sub rows are almost entirely "·" filler
- headers are `white-space: nowrap` uppercase mono (longest:
  `DUPLICATE_RECORD`), so column width is label-driven: estimated table
  min-width **~2,894px ≈ 2.3× a 1280px viewport**
- page weight fine (17.7 KB); `.cs-grid-wrap` has `overflow-x: auto`, sticky
  header row and sticky controller column — so it *functions*: you scroll
  horizontally with the controller name pinned.

**Assessment:** mechanically usable, cognitively poor. One legacy controller
pollutes the **global** column axis: every other controller's row is
whitespace under 28 columns it doesn't route. Ticking "the 5 clerk actions"
means horizontally hunting 5 checkboxes across ~3 screens on a 3-row grid.
Real legacy apps have 10+ such controllers with *different* one-off action
names — columns are the UNION, so the grid grows O(distinct action names)
wide and gets sparser with every controller added.

**README documents it?** The grid is marketed as the hero surface ("Actions
outside any group get their own column" — documented, so the behavior is by
design). The scale consequence is not addressed.

**Proposal:** collapse one-off actions per-row (a disclosure cell "24 custom
actions…" expanding inline), or group columns per controller, or a
per-controller detail page reachable from the row header. Even a
`permission_grid_groups` entry bucketing known report/export verbs would
halve this grid.

## F5. Partial skip propagates to subclasses — inherited escape hatch silently ungates a different permission (major, bug-ish/docs)

**What I did:** Incremental adoption: `skip_before_action
:current_scope_check!, only: [:dashboard]` on `LegacyController`. There is
also `LegacySubController < LegacyController` (routes `legacy_sub#dashboard`,
`#stats`, `#only_here`).

**Expected:** I ungated `legacy#dashboard`. `legacy_sub#dashboard` is a
*different permission key* that nobody granted or skipped.

**Actual:** `legacy_sub#dashboard` is now open to any signed-in user — Rails
inherits the skip. So the escape hatch **fails open across the inheritance
tree**: a subclass someone adds later silently inherits the ungating while
the grid still shows `legacy_sub#dashboard` as a grantable (and apparently
enforced) permission.

**Evidence:** `partial_skip_test.rb` "SURPRISE" test: roleless user GETs
`/legacy_sub/dashboard` → 200; `/legacy_sub/stats` → 403.

**README documents it?** No. It's vanilla Rails callback semantics, but in an
authorization gem the *fail direction is open*, which deserves a loud warning
box next to the skip recipe ("skips are inherited — subclasses of a skipped
controller are skipped too"). The `GatingTripwire` doesn't catch it either:
the gate legitimately didn't run because of the skip.

## F6. Single `current_scope_record` hook forces a hand-rolled action→model dispatch table (minor, dx)

**What I did:** The `:id` actions load three different models
(`toggle_active`→Customer, `print_view`/`duplicate_record`→Widget,
`restore`→Order). The gem offers exactly one hook per controller.

**Actual:** it *works* — the hook is just Ruby, so a
`RECORD_CLASS_BY_ACTION` hash keyed on `action_name` copes fine
(`app/controllers/legacy_controller.rb`) — but the gem gives no per-action
seam, so every god controller hand-maintains that table, and **forgetting an
action is silent**: the hook returns nil, and any scoped grant for that
action is simply inert (fail-closed 403, verified). Verified per-model
correctness: scoped grant on Customer Acme unlocks `toggle_active` on Acme
only (Globex → 403); Widget and Order grants unlock their actions; id
collisions across models can't cross-unlock (`scoped_records_test.rb`).

**Fail direction without the hook (verified before adding it):** org-wide
grant → allowed; scoped grant → 403 `no_grant`. Fail-closed. Correct.

**README documents it?** The hook contract is documented (memoize, use
`request.path_parameters`) but all examples are single-model; nothing on
multi-model controllers, and there is no `warn_on_nil_record`-style dev aid
for "a scoped grant exists for this permission but the gate saw a nil record"
(the existing `warn_on_nil_sod_record` covers only SoD actions).

**Proposal:** a declarative `current_scope_record_for "toggle_active", ->
{ Customer.find(request.path_parameters[:id]) }` macro, and/or extend the nil
nudge: warn when a *denied* member action had scoped grants that could never
match because record was nil.

> **2026-07-19, 0.3.0 (#50):** the F6 silence is half-fixed — a scoped grant
> made inert by a nil record hook now denies with reason `model_undeclared`
> instead of an indistinguishable `no_grant`, and that reason hard-403s even
> in report mode (see F1 note). The per-action seam itself is still absent.

## F7. Record-existence oracle: unauthorized probing distinguishes real ids (403) from fake ids (404) (minor, security)

**What I did:** As a user with **no grants**, POST
`/legacy/<real-customer-id>/toggle_active` and `/legacy/999999/toggle_active`.

**Actual:** real id → **403** (resolver deny); fake id → **404**
(`RecordNotFound` from the hook, which by documented design runs *before* the
decision). Response code therefore leaks whether a record id exists to users
with zero authorization.

**Evidence:** `scoped_records_test.rb` "SECURITY-ADJACENT" test.

**README documents it?** No. The hook-runs-first design is documented; its
enumeration side-channel is not. Standard mitigations (rescue RecordNotFound
inside the hook and return nil → uniform 403… which then changes semantics)
deserve a README note either way.

## F8. `Role#permission_keys=` silently drops unknown keys — typos vanish (minor, dx)

**What I did:** `role.permission_keys = ["legacy#stats",
"legacy#does_not_exist", "legacy#secret_unrouted"]; role.save!`

**Actual:** saves cleanly; reload shows `["legacy#stats"]`. No error, no
warning, no return signal. In seeds/console automation (exactly how a legacy
team will bulk-provision 27-action roles), a typo'd key silently becomes a
missing grant discovered as a production 403.

**Evidence:** `partial_grant_test.rb` last test.

**README documents it?** No. The *code comment* says it's intentional
("dropping keys that aren't in the catalog (stale keys from removed
controllers)") — legitimate for stale keys, hostile for typos.

**Proposal:** keep silent-drop, but expose `role.dropped_permission_keys`
after save, and/or a bang variant/strict mode that raises on unknown keys for
seed-time use.

> **2026-07-19, 0.3.0 (#20):** F8 fixed — unknown keys now make the role
> invalid (`save!` raises, `errors[:permission_keys]` names them);
> `assign_permission_keys(keys, scrub: true)` is the deliberate stale-key
> drop, with `permission_keys_change[:rejected]` reporting what went. See the
> updated test in `partial_grant_test.rb`.

## F9. Ungated controllers still render as grantable grid rows (minor, ux)

**What I did:** `SessionsController` skips the gate entirely (public login
UI), as the README prescribes.

**Actual:** the grid still shows a `sessions` row with read/create/destroy
checkboxes. Ticking them changes nothing (the gate never consults them). The
grid has no visual signal for "this controller/action is ungated" — at
god-controller scale an admin cannot tell dead checkboxes from live ones
(`legacy#dashboard`, skipped in probe 6, likewise still renders as a
grantable column cell).

**README documents it?** No. Related but distinct from the documented
excluded_controllers behavior (exclusion removes the row; skipping does not).

**Proposal:** the grid could grey out known-ungated cells via a
skip registry, or the README should recommend adding fully-skipped
controllers to `excluded_controllers` (which then *forces* the skip via
F10's error — a coherent story that's never spelled out).

## F10. excluded_controllers + Guard = loud, actionable error — works as promised (positive; papercut nit)

**What I did:** Probe 9: `config.excluded_controllers += [%r{\Alegacy\z}]`,
reset catalog, hit `/legacy/stats` as Owner.

**Actual:** `CurrentScope::ConfigurationError`: `"legacy#stats" is not in the
permission catalog (excluded_controllers or not routed). Either stop
excluding it, or skip the gate here with skip_before_action
:current_scope_check!.` Raised for full-access Owner too (correct: it's a
misconfiguration, not a deny). Regex `\Alegacy\z` correctly leaves
`legacy_sub` in the catalog.

**README documents it?** Yes ("Two loud-by-design behaviors…"). The message
names the permission and both fixes — genuinely helpful.

**Nit (papercut):** with several exclusion regexes the message doesn't say
*which* regex matched, and it can't distinguish "excluded" from "not routed"
— it already knows both facts and could say which one applies.

## F11. Doc drift: three bootstrap paths, generator's differs from README (papercut, docs)

The install generator's next-steps text says
`CurrentScope::RoleAssignment.create!(subject: ..., role: Role.find_by!(name: "Owner"))`,
the README says `CurrentScope.grant!(User.first)`, and there's also
`bin/rails current_scope:grant SUBJECT_ID=1`. All work; `grant!` is the
documented idempotent one. The generator should say `CurrentScope.grant!`.

## F12. Host-app papercut: `rails new 03_god_controller` refused (papercut, not the gem)

Rails itself rejects app names starting with digits ("Invalid application
name 03_god_controller"); generated as `god_controller` and renamed the
directory. Not a gem issue — recorded because the scenario mandated the
directory name.

---

## Verified-correct behaviors (no findings)

- **Catalog at god scale:** all 27 routed legacy actions present, exactly
  once (runner dump: 27 legacy + 3 legacy_sub + 3 sessions = 33 keys);
  engine's own controllers excluded by default config.
- **Probe 8 — unrouted action:** `legacy#secret_unrouted` absent from the
  catalog, no phantom permission, URL 404s.
- **Per-action enforcement:** role granted exactly 5 of 27 keys → those 5
  pass, the other 22 all 403 (`partial_grant_test.rb`).
- **Probe 7 — inheritance:** inherited actions surface under the subclass's
  own path (`legacy_sub#stats`), granting the parent key does NOT unlock the
  subclass and vice versa. Catalog does not duplicate the parent's other 24
  actions under `legacy_sub`. Exactly right.
- **Scoped roles:** per-record, per-model correct; id collisions across
  models cannot cross-unlock; missing hook fails closed.
- **Management UI entry:** non-owner → 403; owner → grid renders.
- **`X-Current-Scope-Reason`** present on every denial (`no_grant`), exactly
  as documented.

## Verdict — adopting current_scope in a legacy app, biggest walls first

1. **The 403 wall is total and instant** (F1). The moment Guard lands in
   `ApplicationController`, a 27-action legacy app is 100% dark for every
   user — including the admin who hasn't run the grant rake task yet. There
   is no observe-first mode, so a real team must either big-bang with
   pre-seeded roles, or paper the app in `skip_before_action` lines and walk
   them back one by one — and F5 makes each of those skips a little fail-open
   landmine for subclasses.
2. **Your login UX breaks the same minute** (F2) and nothing tells you why —
   anonymous users see a blank 403 (F3) instead of the sign-in redirect,
   which reads as "the gem broke routing" until you understand callback
   registration order.
3. **The grid was designed for RESTful controllers and it shows** (F4). CRUD
   apps get a tidy 5-column matrix; a god controller gets a 2.3-viewport-wide,
   65%-blank spreadsheet. Fine at 3 controllers, painful at 30.
4. **After the wall, the core model is honest and predictable.** Fail-closed
   everywhere we poked (missing hooks, unmapped actions, id collisions,
   subclass permissions), the catalog is exactly the routes, per-action
   enforcement is exact, and the error on a real misconfiguration (F10) is
   the best part of the DX. The primitives are right; what's missing is the
   *adoption ramp* — monitor mode, a denial-page recipe, callback-order
   guidance, and a grid that survives legacy-shaped route tables.
