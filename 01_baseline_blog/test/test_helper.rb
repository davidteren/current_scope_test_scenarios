ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "current_scope/test_helpers"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include CurrentScope::TestHelpers
  end
end

module SignInHelper
  def login_as(user)
    post sessions_path, params: { user_id: user.id }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
end
