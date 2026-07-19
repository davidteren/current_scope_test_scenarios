ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "current_scope/test_helpers"

module ActiveSupport
  class TestCase
    # Serial: several tests mutate the (process-global) CurrentScope.config.
    parallelize(workers: 1)

    fixtures :all
    include CurrentScope::TestHelpers

    # Flip CurrentScope config knobs for one block, restoring afterwards.
    def with_config(**opts)
      config = CurrentScope.config
      old = opts.keys.index_with { |k| config.public_send(k) }
      opts.each { |k, v| config.public_send(:"#{k}=", v) }
      yield
    ensure
      old.each { |k, v| config.public_send(:"#{k}=", v) }
    end
  end
end

module SodMatrixSetup
  def create_people_and_roles
    @alice = User.create!(name: "Alice", email: "alice@x.com")   # admin / initiator in most probes
    @bob   = User.create!(name: "Bob", email: "bob@x.com")       # non-initiating approver
    @owner    = CurrentScope::Role.create!(name: "Owner", full_access: true)
    @approver = CurrentScope::Role.create!(name: "Approver")
    @approver.update!(permission_keys: %w[
      expenses#index expenses#show expenses#approve expenses#reject expenses#approve_all
      invoices#index invoices#show invoices#approve
    ])
  end

  def sign_in(user)
    post login_path(user)
  end

  def impersonate(user)
    post impersonation_path, params: { subject_id: user.id }
  end
end
