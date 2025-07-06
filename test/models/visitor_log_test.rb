require "test_helper"

class VisitorLogTest < ActiveSupport::TestCase
  test "track creates or updates unique log" do
    assert_difference("VisitorLog.count", 1) do
      VisitorLog.track(ip: "1.1.1.1", agent: "Mozilla", path: "/home")
    end

    log = VisitorLog.last
    assert_equal 1, log.visit_count

    assert_no_difference("VisitorLog.count") do
      VisitorLog.track(ip: "1.1.1.1", agent: "Mozilla", path: "/home")
    end

    log.reload
    assert_equal 2, log.visit_count
  end
end
