require "test_helper"

class Admin::VisitorLogsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_visitor_logs_index_url
    assert_response :success
  end
end
