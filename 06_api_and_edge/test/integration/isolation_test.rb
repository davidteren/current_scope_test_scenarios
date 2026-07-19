require "test_helper"

# Probe 5: CurrentAttributes isolation across requests and jobs.
class IsolationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { create_users_and_roles! }

  test "no leakage between two sequential API requests as different users" do
    get "/api/v1/items", headers: bearer(@owner)
    assert_response :success

    get "/api/v1/items" # anonymous, immediately after
    assert_response :forbidden

    get "/api/v1/items", headers: bearer(@nobody)
    assert_response :forbidden

    assert_nil CurrentScope::Current.user, "Current must be reset after the request cycle"
  end

  test "no leakage between two sequential HTML sessions" do
    post "/sessions", params: { user_id: @owner.id }
    get "/items"
    assert_response :success

    post "/sessions", params: { user_id: @nobody.id }
    get "/items"
    assert_response :forbidden
  end

  test "Current does NOT flow into an Active Job" do
    ProbeJob.seen_user = :sentinel
    with_current_user(@owner) do
      perform_enqueued_jobs { ProbeJob.perform_later }
    end
    assert_nil ProbeJob.seen_user, "job must not see the enqueuing request's subject"
  end
end
