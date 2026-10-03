require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get imports_create_url
    assert_response :success
  end
end
