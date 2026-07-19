ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "current_scope/test_helpers"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include CurrentScope::TestHelpers

    def seed_roles!
      CurrentScope.seed_defaults!
      @owner_role  = CurrentScope::Role.find_by!(name: "Owner")
      @member_role = CurrentScope::Role.find_by!(name: "Member")
    end

    def make_role!(name, keys)
      CurrentScope::Role.create!(name: name).tap do |r|
        r.permission_keys = keys
        r.save!
      end
    end
  end
end

module ActionDispatch
  class IntegrationTest
    def sign_in(user)
      post sessions_path(user_id: user.id)
    end
  end
end
