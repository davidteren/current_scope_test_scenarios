CurrentScope.configure do |config|
  # Impersonation-aware subject resolution (README act-as recipe): the
  # effective subject re-resolves from the session each request; the real
  # actor is always the signed-in account.
  config.user_method  = :current_scope_user
  config.actor_method = :true_user

  # Scenario 9 needs impersonated POSTs to pass the mutation gate. Fine
  # outside production (raises at boot in production without the env opt-in).
  config.allow_mutations_while_impersonating = true

  # SoD baseline for the whole matrix; individual tests mutate config knobs
  # (sod_actions, allow_sod_bypass, sod_identity, warn_on_nil_sod_record,
  # audit) around requests and restore them.
  config.sod_actions = %w[approve]
end
