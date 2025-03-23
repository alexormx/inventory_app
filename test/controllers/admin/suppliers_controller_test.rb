require "test_helper"

class Admin::SuppliersControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_suppliers_index_url
    assert_response :success
  end

  test "should get new" do
    get admin_suppliers_new_url
    assert_response :success
  end

  test "should get create" do
    get admin_suppliers_create_url
    assert_response :success
  end

  test "should get edit" do
    get admin_suppliers_edit_url
    assert_response :success
  end

  test "should get update" do
    get admin_suppliers_update_url
    assert_response :success
  end
end
