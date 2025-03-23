require "test_helper"

class Admin::CustomersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_customers_index_url
    assert_response :success
  end

  test "should get new" do
    get admin_customers_new_url
    assert_response :success
  end

  test "should get create" do
    get admin_customers_create_url
    assert_response :success
  end

  test "should get edit" do
    get admin_customers_edit_url
    assert_response :success
  end

  test "should get update" do
    get admin_customers_update_url
    assert_response :success
  end
end
