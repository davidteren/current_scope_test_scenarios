# FINDINGS — 04_sod_matrix (SoD config matrix, current_scope v0.2.0)

Host app: expenses (Expense with initiator + bypass hooks, Invoice deliberately
without hooks). All scenarios exercised via `bin/rails test`
(26 runs, 77 assertions, 0 failures) plus `bin/rails runner` probes.
Test files: `test/integration/sod_matrix_test.rb`, `test/integration/break_glass_test.rb`,
`test/integration/impersonation_and_audit_test.rb`.

Verified-working behaviors (no finding): baseline veto over full_access (403 +
`X-Current-Scope-Reason: sod_veto`), non-initiator approval, SoD-off mode
needing no hooks, loud `ConfigurationError` for a missing initiator hook with a
genuinely excellent message, nil-initiator exemption, the documented nil-record
skip, break-glass matrix rows (config off / record flag off / no permission /
missing hook -> vetoed; all three held -> allowed + exactly one `sod.bypassed`
event + `sod_bypassed` header), `sod_identity` `:either` vs `:subject` under
impersonation, audit tri-state incl. graceful degrade and `:strict` rollback on
a missing events table. Denials are rescued BY THE ENGINE (rescue_from in
MutationGuard, included via Guard) -> hosts get 403 + reason header with zero
work; the README never needs to tell hosts to rescue and correctly doesn't.

---

## F1 (major, docs+ux): `bypass_sod` is not grantable anywhere in the UI — README claims it is

- **What I did:** Enabled break-glass, then tried to grant the default
  `bypass_sod` permission to a non-full-access role: (a) via the role grid at
  `/current_scope/roles/:id/edit`, (b) via `role.permission_keys=`.
- **Expected:** README break-glass section: `config.sod_bypass_permission =
  "bypass_sod" # grantable, editable in the role grid`. Configuration doc
  comment: "Resolved against the record's route key like any permission, so
  it's editable in the role grid — never a hardcoded role."
- **Actual:** The permission catalog is derived exclusively from routes
  (`PermissionCatalog#derive`). `bypass_sod` is not a routed action, so
  `expenses#bypass_sod` is not in the catalog; the grid (columns = routed
  actions) never renders a cell for it. Verified: grid HTML for a role contains
  no occurrence of `bypass_sod` (test 8b); columns present are the CRUD groups
  plus routed customs `approve`, `approve_all`, `reject`.
- **How to grant it at all:** only (1) `role.role_permissions.create!(permission_key:
  "expenses#bypass_sod")` in a console, or (2) full_access (grants everything,
  see F3), or (3) routing a dummy `bypass_sod` action so it enters the catalog.
  An admin using only the shipped UI cannot set up the documented break-glass
  "trusted admin" role.
- **README documented?** No — the README/config comments assert the opposite.
- **Evidence:** test 8b green (`refute_includes response.body, "bypass_sod"`);
  `CurrentScope.permission_key("bypass_sod", record: expense)` => `"expenses#bypass_sod"`;
  catalog dump contains no `bypass_sod` key.

## F2 (major, dx): `Role#permission_keys=` silently drops non-catalog keys — no error, no log

- **What I did:** `role.update!(permission_keys: %w[expenses#bypass_sod expenses#approve])`
- **Expected:** Either the key persists, or a validation error / warning says
  it was rejected.
- **Actual:** `role.reload.permission_keys == ["expenses#approve"]` — the
  bypass key vanished silently (test 8a). The setter filters through
  `CurrentScope.catalog.include?` with no feedback. Combined with F1 this makes
  break-glass setup fail invisibly: seeds that look correct produce a role that
  can never bypass, and the veto 403 that follows gives no hint why.
- **README documented?** Partially — "dropping keys that aren't in the catalog
  (stale keys from removed controllers)" is the stated intent in code comments;
  the silent-drop interaction with `sod_bypass_permission` is not documented
  anywhere.
- **Evidence:** test 8a: `assert_equal %w[expenses#approve], role.reload.permission_keys`.
- **2026-07-19 — 0.3.0: fixed by #20.** `permission_keys=` now fails validation
  loudly, naming the unknown keys; `assign_permission_keys(..., scrub: true)` is
  the deliberate opt-in to the old drop. See test 8a (re-pinned to the new
  behavior). F1 itself (bypass_sod ungrantable via UI) remains, tracked in #21.

## F3 (minor, docs): full_access implicitly holds the bypass permission — "veto overrides full access" stops being true once break-glass is on

- **What I did:** allow_sod_bypass on, record flag on, initiator holds only
  full_access Owner (no explicit `bypass_sod` grant). Initiator approves own
  expense.
- **Expected (per README framing):** "whoever initiated a record can never
  approve it — overrides even full access"; the bypass requires the initiator
  to "hold the bypass permission".
- **Actual:** ALLOWED with `X-Current-Scope-Reason: sod_bypassed` (test 6d).
  The inner bypass check is an ordinary resolve, and full_access grants every
  permission — including `expenses#bypass_sod` (and any `sod_bypass_permission`
  value: a probe with `"audit/bypasses#grant"` also passed for an Owner). So
  enabling `allow_sod_bypass` means every full-access user is automatically
  bypass-privileged on any record they can flag. Consistent with "full_access
  grants everything", and it is audited — but the README's break-glass section
  never says "full_access holders always satisfy condition 3", which is exactly
  the population (admins) SoD usually targets.
- **README documented?** Not explicitly; derivable from the decision order.
- **Evidence:** test 6d green; runner probe `full-key bypass, no such grant: true`.

## F4 (major, docs): collection actions listed in `sod_actions` are silent no-ops — bulk self-approval is a designed hole

- **What I did:** `config.sod_actions = %w[approve approve_all]`; initiator (with
  an approve_all grant) POSTs the collection action `approve_all` while their own
  expense is in the batch.
- **Expected:** Some veto, warning, or documented refusal.
- **Actual:** 200, everyone's expenses "approved" including the initiator's own
  (test 5). `current_scope_record` is legitimately nil on a collection action,
  and a nil record skips the veto by design — so listing a collection action in
  `sod_actions` does nothing at all. A team that gates `approve` but ships
  `approve_all` has bypassable SoD; the engine gives no signal that a listed
  action can never be enforced (it could detect "action routed only as a
  collection route" at boot).
- **Mitigation available (works, unadvertised):** advisory checks honor the
  veto — `records.select { |r| allowed_to?(:approve, r) }` inside the bulk
  action gives per-record SoD. Runner probe confirmed the advisory path returns
  false for the initiator's own record even for a full_access subject.
- **README documented?** Obliquely at best: "nil is legitimate for collection
  actions, so the resolver can't tell the two apart" and "SoD ... vetoes
  record-targeted actions". There is no explicit "bulk actions cannot be
  SoD-gated; decompose them" warning or recipe.
- **Evidence:** test 5 green: `post approve_all_expenses_path` -> 200,
  "approved all 2 expenses".

## F5 (minor, dx): the bypass-in-sod_actions guard rail fires at decision time only, behind three preconditions — misconfig ships silently

- **What I did:** `config.sod_actions = %w[approve bypass_sod]` (the exact
  misconfiguration the engine documents as forbidden), then probed when the
  promised raise happens.
- **Expected:** raise at boot/config time ("the engine raises if it does").
- **Actual:** App boots and serves fine. The `ConfigurationError` ("must not be
  an SoD action — it would recurse") is raised only when ALL of: (1)
  `allow_sod_bypass = true`, (2) an SoD action hits, (3) the requester is the
  initiator (a live conflict). With `allow_sod_bypass = false` the misconfig is
  never detected (test 7b); a non-initiator sails through undetected (test 7c);
  the first initiator to hit a conflict gets a production 500 (test 7a). The
  raise message itself is excellent.
- **README documented?** README says "the engine raises if it does" without
  saying when; the fine-grained dormancy is undocumented.
- **Evidence:** tests 7a/7b/7c all green with those exact behaviors.

## F6 (minor, dx): `warn_on_nil_sod_record` works but is not discoverable by the team that needs it

- **What I did:** Simulated the documented nil-record mistake
  (`current_scope_record` returns nil on `approve`), confirmed the veto is
  skipped (test 4a, initiator self-approved with 200), then set
  `config.warn_on_nil_sod_record = true` and grepped `log/test.log`.
- **Actual:** Warning logs exactly as promised:
  `[CurrentScope] "expenses#approve" is a separation-of-duties action but was
  gated with a nil record, so the SoD veto was skipped. ...` (test 4b).
- **DX opinion:** the flag is off by default, mentioned once in a README aside
  and once in an initializer comment. The team that made the nil-record mistake
  doesn't know they made it — precisely why they'll never enable the flag that
  reveals it. It "never changes behavior" and only logs at warn level, so there
  is no cost to defaulting it ON in dev/test (or raising in dev). As shipped, a
  real team would find the skipped veto in an incident review, not in the log.
- **README documented?** The foot-gun itself is documented well ("the one
  asymmetry to know"); the discoverability problem is the finding.

## F7 (papercut, dx): audit events never get a `request_id` — the column exists, nothing fills it

- **What I did:** Inspected `current_scope_events` rows created through real
  requests (engine UI grant, sod.bypassed).
- **Expected:** `request_id` correlation metadata populated from
  `request.request_id` (ActionDispatch::RequestId runs on every request).
- **Actual:** `request_id: nil` on every row. `Current.request_id` exists and
  `Event.record!` stamps it, but `Context#set_current_scope_user` never sets it
  and no README section tells the host to. A one-line addition to Context (or a
  documented host recipe) would make the ledger correlatable with app logs.
- **README documented?** Not mentioned at all.

## F8 (papercut, docs): install generator's "next steps" suggest a non-idempotent grant, diverging from the README

- **What I did:** Ran `bin/rails generate current_scope:install`.
- **Actual:** Post-install text suggests
  `CurrentScope::RoleAssignment.create!(subject: User.first, role: ...)` for
  seeds — raises on re-run (seeds should be idempotent; uniqueness on subject).
  The README recommends the idempotent `CurrentScope.grant!(User.first)` and a
  `current_scope:grant` rake task. The generator should say the same thing.

## F9 (papercut, ux): denials are a bare `head :forbidden` — blank page for humans, no documented override seam

- **What I did:** Hit vetoed/no-grant endpoints as a browser would.
- **Actual:** 403 with empty body (`MutationGuard#current_scope_denied` does
  `head :forbidden`). Machine-readable header is great for APIs/tests; a human
  in a server-rendered app gets a white page. The rescue handler is a private
  method a host could override or re-`rescue_from`, but neither is documented.
  A short README note ("override `current_scope_denied` to render your own 403
  page") would cover it.
- **README documented?** The header is documented; the blank-page behavior and
  the override seam are not.

---

## Scenario-by-scenario outcomes

1. Baseline veto: PASS as documented. 403 + `sod_veto` header; deny overrides
   full_access; non-initiator with grant allowed. Denial produces 403 (never a
   500) because the engine's own `rescue_from` handles `AccessDenied`.
2. SoD off: PASS. Same POST returns 200; Invoice (hook-less) approvable; config
   mutation mid-suite works because the resolver reads config live.
3. Missing hook: PASS, loud. Exact message: `Invoice#current_scope_initiator is
   not defined, but "invoices#approve" is a separation-of-duties action
   (config.sod_actions). Define current_scope_initiator on Invoice (return nil
   to exempt a record), or remove "approve" from config.sod_actions.` — names
   the class, the key, both fixes. Model-quality error. Nil hook -> exempt/allowed.
4. nil-record foot-gun: behaves exactly as documented (veto skipped, 200);
   warning logs when enabled (F6 on discoverability).
5. approve_all: hole confirmed (F4).
6. Break-glass matrix: all rows behave as specified; exactly one `sod.bypassed`
   event with permission + initiator GID in details; header set. Full-access
   nuance is F3.
7. Guard rail: decision-time only, three preconditions (F5).
8. Grid: `bypass_sod` appears nowhere; ungrantable via UI (F1/F2).
9. sod_identity: `:either` vetoes the impersonating initiator (403 sod_veto),
   `:subject` allows — both verified with real session-based impersonation and
   `allow_mutations_while_impersonating = true`.
10. Audit tri-state: `false` -> zero rows, grant still commits; `true` -> rows
    with correct actor/target GIDs; `:strict` normal with table present;
    missing table: `true` degrades with a clear one-time warning, `:strict`
    raises and rolls the grant back. All as documented. (`request_id` gap: F7.)
