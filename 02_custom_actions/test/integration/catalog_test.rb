require "test_helper"

# Probe 1 + 7 + 8: catalog contents for custom / non-resourceful / multi-verb routes.
class CatalogTest < ActiveSupport::TestCase
  CUSTOM = %w[approve reject publish archive clone export bulk_archive search preview_all]

  test "all 9 custom reports actions appear exactly once" do
    keys = CurrentScope.catalog.keys
    CUSTOM.each do |a|
      assert_equal 1, keys.count("reports##{a}"), "reports##{a} missing or duplicated in #{keys}"
    end
  end

  test "match via get+post yields exactly ONE search permission" do
    assert_equal 1, CurrentScope.catalog.keys.count("reports#search")
  end

  test "non-resourceful wizard controller is fully cataloged" do
    %w[step_one submit_step_one step_two complete].each do |a|
      assert_includes CurrentScope.catalog.keys, "wizard##{a}"
    end
  end

  test "no duplicates, infrastructure controllers excluded by default" do
    keys = CurrentScope.catalog.keys
    assert_equal keys.uniq.sort, keys
    assert_empty keys.grep(%r{\Arails/}), "rails internal controllers leaked into catalog"
    assert_empty keys.grep(%r{\Acurrent_scope/}), "engine controllers leaked into catalog"
  end
end
