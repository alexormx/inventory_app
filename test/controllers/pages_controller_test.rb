require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should get privacy_notice" do
    get pages_privacy_notice_url
    assert_response :success
  end
end
