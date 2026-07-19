ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "current_scope/test_helpers"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include CurrentScope::TestHelpers
  end
end

module AuthProbeHelpers
  def login_as(user)
    post "/sessions", params: { user_id: user.id }
  end

  def make_owner!(user)
    CurrentScope.seed_defaults!
    CurrentScope.grant!(user)
  end
end

class ActionDispatch::IntegrationTest
  include AuthProbeHelpers
end
