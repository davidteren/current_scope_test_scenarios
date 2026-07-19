# FINDINGS — 06_api_and_edge (API controllers, GatingTripwire, routing edge cases)

Host: Rails 8.1.3 / ruby 3.4.9, current_scope v0.2.0 by path. Hybrid app:
HTML (sessions + items index, Pico CDN) + `Api::BaseController < ActionController::API`
with Bearer-token auth, `Api::V1::ItemsController` (index/show/create/destroy + member publish).
All probes are integration tests (`bin/rails test`, 32 tests green) plus `bin/rails runner` probes.

Severity: blocker / major / minor / papercut.

---

## F1 (MAJOR, bug/design): scoped-only subjects are locked out of gated collection actions — `scope_for`'s scoped path is unreachable behind its own gate

**What I did:** Gave a user NO org-wide role, only a scoped role (grants
`api/v1/items#index` + `api/v1/items#show`) on one Item, then hit the gated
API index.

**Expected (per README):** The `scope_for` index recipe ("scoped grants → only
the specific records that role was granted on") implies a scoped-only user can
reach the index and see their records.

**Actual:** 403 at the gate. Runner probe output:

```
gate decide index (record=nil): [false, :no_grant]
scope_for index:                 ["Bucket"]          # the correct scoped subset!
allow? index on bucket:          true                # per-record check passes!
```

The Guard calls `current_scope_record`, which is (correctly, per the gem's own
docs) nil for collection actions — and the resolver's scoped-grant branch
requires a record instance, so scoped grants are invisible to every collection
gate. The subject 403s at the door of the very list whose contents `scope_for`
would correctly return.

The flip side closes the loop: granting the index key **org-wide** passes the
gate but makes `scope_for` return `model.all` (org grant of the checked
permission → every record). So **no grant combination produces a gated index
that lists only the scoped subset when keyed on the default index permission**.
Hosts must either (a) skip the gate on index and rely on scope_for's empty
relation, or (b) grant index org-wide and call
`scope_for(Item, permission: :show)` — filtering on a member permission —
neither of which the README teaches.

**Docs status:** NOT documented. The README's `scope_for` section and the
"Every record scope_for returns passes allowed_to?(:index, project)" claim are
both technically true but hide that the *gate* disagrees for scoped-only
subjects. This deserves either a resolver change (collection actions pass if
the subject holds ANY scoped grant of the key, with scope_for narrowing the
list) or a loud README warning + blessed pattern.

**Repro:** `test/integration/api_guard_test.rb` — "scoped-only subject is
DENIED the index action even though scope_for would list records".

> **0.3.0 (2026-07-19): fixed by #50/#65.** Declaring `current_scope_model` on
> the controller opens the record-less gate (index answers from
> `scope_for(...).exists?`); without the hook the denial reason is now
> `model_undeclared`, naming the fix — see the updated test above.

---

## F2 (MINOR, docs): out-of-box denial rendering is undocumented — it is a 403 with an EMPTY body (not a 500), and the README says nothing about it or about the JSON API pattern

**What I did:** Hit a gated `ActionController::API` controller (no custom
rescue) with no grant; also hit a gated HTML controller.

**Expected:** The README documents `AccessDenied` + the reason header, so I
expected either "denial = raised exception = host must rescue (else 500)" or
documentation of the built-in rendering.

**Actual (good behavior, zero docs):** `CurrentScope::MutationGuard` (pulled in
by Guard) quietly installs `rescue_from CurrentScope::AccessDenied` →
`head :forbidden` + `X-Current-Scope-Reason`. Out-of-box on the API:

```
status: 403
body:   ""            (empty — no JSON error object)
header: X-Current-Scope-Reason: no_grant
```

Same for HTML: a browser gets a completely blank 403 page. It is NOT an HTML
500 — good — but a JSON API returning an empty body with a bespoke header is
weak DX for API consumers, and a blank page is weak UX for browsers.

**Working fix pattern (verified):** register your own rescue AFTER including
Guard — later `rescue_from` registrations win:

```ruby
rescue_from CurrentScope::AccessDenied do |e|
  response.set_header("X-Current-Scope-Reason", e.reason.to_s) if e.reason
  render json: { error: "forbidden", reason: e.reason }, status: :forbidden
end
```

**Docs status:** README never mentions the built-in rescue_from, the empty-body
403, or an API/JSON pattern. Finding = docs gap, not behavior bug.

**Repro:** `api_guard_test.rb` — "OUT-OF-BOX denial…" and "custom rescue_from
gives a JSON error body".

---

## F3 (MINOR, ux/dx): phantom permissions — a route to a nonexistent controller becomes a normal, grantable grid row

**What I did:** `get "ghosts" => "ghosts#index"` with no `GhostsController`;
dumped the catalog and the role-edit grid.

**Actual:**
- `CurrentScope.catalog.include?("ghosts#index")` → true.
- The grid renders a `ghosts` row visually identical to real controllers:
  `<input type="checkbox" ... value="ghosts:read" aria-label="ghosts read">`,
  plus an "Enable all ghosts permissions" row toggle. Fully tickable; the key
  persists through `permission_keys=` (it IS in the catalog, so the stale-key
  filter passes it).
- Hitting `/ghosts` raises `ActionDispatch::MissingController: uninitialized
  constant GhostsController` — which is NOT a rescuable error, so production
  serves a **500**, not a 404 (that part is Rails behavior, not the gem's).

So a stale/typo route pollutes the grid with a grantable no-op permission and
nothing in the UI hints the controller doesn't exist. An admin can "grant"
ghosts:read and wonder why nothing changes.

**Docs status:** not mentioned. `excluded_controllers` can hide it once you
notice, but there's no signal to notice.

**Repro:** `routing_edges_test.rb` (b); `management_ui_test.rb` grid dump.

---

## F4 (PAPERCUT, ux): every unique custom action name becomes a grid-wide column; ungated/skip-gated controllers still get grantable rows

**Actual grid for this small app** (8 rows):

```
["Controller", "read", "create", "destroy", "boom", "health", "publish", "secret"]
["api/halted",  ...blank...]
["api/health",  ...]
["api/raw",     ...]
["api/v1/items",...]
["ghosts",      ...]
["items",       ...]
["sessions",    ...]
```

- `boom`, `health`, `secret` come from tripwire-probe/health controllers that
  are never gated — yet they add columns to EVERY row (blank cells elsewhere).
  A real app with many custom actions gets a very wide grid; infra controllers
  must be manually excluded via `excluded_controllers`.
- `sessions` (which does `skip_before_action :current_scope_check!`) still
  renders as a grantable row; ticking it does nothing. The grid can't know an
  action is skip-gated, so admins can grant permissions with zero effect.

**Docs status:** `excluded_controllers` is documented for infra ("keep
infrastructure out of the grid"), so partially a known design decision; the
column-per-custom-action layout and grantable-but-skipped rows are not called out.

---

## F5 (MINOR, security): 403-vs-404 existence oracle, and record loads before any grant check

**What I did:** As an anonymous caller (no token): `GET /api/v1/items/1`
(exists) vs `GET /api/v1/items/999999` (doesn't).

**Actual:** existing id → **403** (`X-Current-Scope-Reason: no_grant`); missing
id → **404** (`RecordNotFound` from `current_scope_record`'s `Item.find`). An
unauthenticated caller can enumerate which ids exist. Also note the ordering:
the Guard invokes `current_scope_record` BEFORE the resolver decides, so
anonymous requests trigger real DB record loads.

This follows directly from the README's own recommended
`current_scope_record` recipe. Pundit-style docs usually mention the
"rescue denial as 404 to avoid leaking existence" option; this README doesn't.

**Docs status:** not mentioned. Host-solvable (rescue AccessDenied → 404 for
member actions), but the trade-off should be documented.

**Repro:** `api_guard_test.rb` — "existing id yields 403, missing id yields 404".

---

## F6 (MINOR, dx): hybrid HTML+API apps must grant every resource twice — `items#index` does not imply `api/v1/items#index`

**What I did:** Role granting only `items#index`; user can load the HTML items
page (200) but gets 403 from `GET /api/v1/items`.

**Actual/Expected:** By design — controller#action IS the permission. But a
hybrid app ends up with parallel `items` and `api/v1/items` grid rows that an
admin must keep ticking in tandem, and nothing groups or links them. The README
covers the namespaced-key foot-gun for `allowed_to?` derivation, not the
dual-grant burden on hybrid apps.

**Docs status:** adjacent foot-gun documented; this specific consequence not.

**Repro:** `api_guard_test.rb` — "hybrid apps need BOTH keys granted".

---

## F7 (PAPERCUT, dx): engine management-UI denial carries no `X-Current-Scope-Reason` header

`require_full_access!` renders a bare `head :forbidden` with no reason header,
while every Guard denial sets `X-Current-Scope-Reason`. Diagnosing "why can't
this admin open /current_scope" from the response alone is therefore blind.
Verified: member GET `/current_scope/` → 403, header nil.

**Repro:** `management_ui_test.rb` — "only full-access subjects enter…".

> **0.3.0 (2026-07-19): fixed by #23.** The engine UI denial now raises
> `AccessDenied` and carries `X-Current-Scope-Reason: not_full_access` —
> see the updated test above.

---

## F8 (PAPERCUT, code-read, PLAUSIBLE): MutationGuard treats OPTIONS as a mutation

`current_scope_mutation_guard!` exempts only `request.get? || request.head?`.
A routed OPTIONS action (e.g. an app serving CORS preflight from a controller)
would be denied while impersonating, though OPTIONS never mutates. Confirmed
non-impersonating behavior: OPTIONS routed to a gated action passes the
mutation guard and is permission-gated like any request (200 as owner, 403
signed-out — `routing_edges_test.rb`). The impersonation branch is from code
reading only (actor_method unset in this app).

---

## Confirmed-good (explicitly probed, behaved as documented)

- **Context + Guard on `ActionController::API` work unmodified** (probe 1):
  no helpers/flash/redirect assumptions bit us. `Context`'s
  `if respond_to?(:helper_method)` guard handles API controllers; token auth
  via the global `user_method = :current_user` name works — though note the
  method name is GLOBAL config, so every base (HTML session auth, API token
  auth) must expose the same name.
- **GatingTripwire** (probe 3): (a) gated action → no raise; (b) ungated action
  on a tripwired base raises after the action with exactly:
  `"api/health#boom" completed without running current_scope_check! — this
  controller is not gated by CurrentScope::Guard. Include CurrentScope::Guard
  on its base controller, or mark this action public with
  current_scope_skip_tripwire! only: :boom` (500 in a live env, loud in test);
  (c) `current_scope_skip_tripwire! only: :health` → 200, no raise;
  (d) documented blind spot confirmed — render from a `before_action` (halted
  chain) escapes the tripwire entirely (200, leaked body, no raise).
- **Catalog sanity** (probe 4): rack `proc` route skipped; `redirect(...)`
  route skipped; `scope module:` route keyed under its module path
  (`api/health#health`); two paths → same controller#action dedupe to ONE
  permission; constrained route gated normally when matched / 404 when not;
  engine's own routes (and `rails/*`) absent from the catalog.
- **CurrentAttributes isolation** (probe 5): sequential requests as different
  users show zero leakage (owner 200 → anonymous 403 → other user 403);
  `CurrentScope::Current.user` is nil after the request cycle; a job enqueued
  inside `with_current_user` sees `Current.user == nil` in `perform`
  (matches the README's "does not flow into Active Job").
- **scope_for on the API index** (probe 6): full access → all; org grant → all;
  member-permission-keyed scoped query returns exactly the granted records.
  (The gate-level asymmetry is F1.)
- **Odd verbs** (probe 8): HEAD passes the mutation guard, is still
  permission-gated (200 with grant, 403 without); un-routed OPTIONS → 404
  before any gate; wrong verb on a member route → 404 before any gate.

## Build friction (not gem findings)

- `rails new 06_api_and_edge` rejects a leading digit; needed `--name api_edge`.
- Driving an `ActionDispatch::Integration::Session` inside `bin/rails runner`
  crashes on Rails 8.1 (`ExecutionContext.to_h.merge` on nil) — grid HTML
  inspection had to live in an integration test instead.
