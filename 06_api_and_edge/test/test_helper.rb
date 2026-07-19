ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "current_scope/test_helpers"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    include CurrentScope::TestHelpers

    # No fixtures — each test builds what it needs.
    def create_users_and_roles!
      CurrentScope.seed_defaults!
      @owner  = User.create!(name: "Olive Owner",  email: "owner@t.test",  api_token: "owner-token")
      @member = User.create!(name: "Manny Member", email: "member@t.test", api_token: "member-token")
      @nobody = User.create!(name: "Nadia Nobody", email: "nobody@t.test", api_token: "nobody-token")
      @owner_role  = CurrentScope::Role.find_by!(name: "Owner")
      @member_role = CurrentScope::Role.find_by!(name: "Member")
      @member_role.role_permissions.create!(permission_key: "api/v1/items#index")
      @member_role.role_permissions.create!(permission_key: "items#index")
      grant_role!(@owner, role: @owner_role)
      grant_role!(@member, role: @member_role)
      @anvil  = Item.create!(name: "Anvil",  user: @owner)
      @bucket = Item.create!(name: "Bucket", user: @member)
      @crate  = Item.create!(name: "Crate",  user: @owner)
    end

    def bearer(user)
      { "Authorization" => "Bearer #{user.api_token}" }
    end
  end
end
