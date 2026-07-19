require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @comment = comments(:one)
    # CurrentScope is fail-closed: without this, every scaffold test 403s.
    CurrentScope.seed_defaults!
    admin = User.create!(name: "Test Admin", email: "admin@t.example")
    grant_role!(admin, role: CurrentScope::Role.find_by!(name: "Owner"))
    login_as admin
  end

  test "should get index" do
    get comments_url
    assert_response :success
  end

  test "should get new" do
    get new_comment_url
    assert_response :success
  end

  test "should create comment" do
    assert_difference("Comment.count") do
      post comments_url, params: { comment: { body: @comment.body, post_id: @comment.post_id } }
    end

    assert_redirected_to comment_url(Comment.last)
  end

  test "should show comment" do
    get comment_url(@comment)
    assert_response :success
  end

  test "should get edit" do
    get edit_comment_url(@comment)
    assert_response :success
  end

  test "should update comment" do
    patch comment_url(@comment), params: { comment: { body: @comment.body, post_id: @comment.post_id } }
    assert_redirected_to comment_url(@comment)
  end

  test "should destroy comment" do
    assert_difference("Comment.count", -1) do
      delete comment_url(@comment)
    end

    assert_redirected_to comments_url
  end
end
