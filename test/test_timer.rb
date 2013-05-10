require 'rubygems'
require 'bud'
require 'test/unit'

require 'progress_timer'

# run with
# ruby -I/[path to raft directory] -I. test_timer.rb

class RealTimer
  include Bud
  include ProgressTimer

  state do
    table :alarms, [:timestamp]
  end

  bloom do
    alarms <= alarm {|a| [budtime]}
  end
end

class TestTimer < Test::Unit::TestCase
  def test_alarm_going_off
    timer = RealTimer.new
    timer.run_bg
    # set timer for 3 seconds
    timer.async_do { timer.set_alarm <+ [[3000]] }
    # wait a second and make sure the alarm doesn't go off
    sleep 1
    assert_equal(0, timer.alarms.length)
    # wait another second and make sure it's still not off
    sleep 1
    assert_equal(0, timer.alarms.length)
    # wait 1.5 more seconds and the alarm should have went off
    sleep 1.5
    assert_equal(1, timer.alarms.length)
  end

  def test_multiple_alarms
    timer = RealTimer.new
    timer.run_bg
    # set timer for 3 seconds
    timer.async_do { timer.set_alarm <+ [[3000]] }
    # wait a second and make sure the alarm doesn't go off
    sleep 1
    assert_equal(0, timer.alarms.length)
    # wait 3 more seconds and the alarm should have went off
    sleep 3
    assert_equal(1, timer.alarms.length)
    # set another alarm and make sure it doesn't go off after a second
    timer.async_do { timer.set_alarm <+ [[3000]] }
    sleep 1
    assert_equal(1, timer.alarms.length)
    # make sure it goes off after another 3 seconds
    sleep 3
    assert_equal(2, timer.alarms.length)
  end

  def test_reset_alarm
    timer = RealTimer.new
    timer.run_bg
    # set timer for 3 seconds
    timer.async_do { timer.set_alarm <+ [[3000]] }
    # wait 2 seconds and make sure alarm doesn't go off
    sleep 2
    assert_equal(0, timer.alarms.length)
    # reset the alarm
    timer.async_do { timer.set_alarm <+ [[3000]] }
    # wait another 2 seconds and the alarm should not have went off still
    sleep 2
    assert_equal(0, timer.alarms.length)
    # wait another 1.5 seconds and it should go off
    sleep 1.5
    assert_equal(1, timer.alarms.length)
  end
end