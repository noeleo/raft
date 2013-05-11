require 'rubygems'
require 'bud'
require 'test/unit'

require 'snooze_timer'

# run with
# ruby -I/[path to raft directory] -I. test/test_timer.rb

class RealTimer
  include Bud
  include SnoozeTimer

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
    timer.sync_do { timer.set_alarm <+ [[3000]] }
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
    timer.sync_do { timer.set_alarm <+ [[3000]] }
    # wait a second and make sure the alarm doesn't go off
    sleep 1
    assert_equal(0, timer.alarms.length)
    # wait 3 more seconds and the alarm should have went off
    sleep 3
    assert_equal(1, timer.alarms.length)
    # set another alarm and make sure it doesn't go off after a second
    timer.sync_do { timer.set_alarm <+ [[3000]] }
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
    timer.sync_do { timer.set_alarm <+ [[3000]] }
    # wait 1.5 seconds and make sure alarm doesn't go off
    sleep 1.5
    assert_equal(0, timer.alarms.length)
    # reset the alarm
    timer.sync_do { timer.set_alarm <+ [[3000]] }
    # wait another 2 seconds and the alarm should not have went off still
    sleep 2
    assert_equal(0, timer.alarms.length)
    # wait another 1.5 seconds and it should go off
    sleep 1.5
    assert_equal(1, timer.alarms.length)
  end

  # this doesn't work in actual operation... should be key constraint error, should it not?
  def test_multiple_timers_at_same_tick
    timer = RealTimer.new
    timer.run_bg
    # set timers for 3 seconds
    timer.sync_do { timer.set_alarm <+ [[3000], [3000]] }
    # wait a second and make sure alarm doesn't go off
    sleep 1
    assert_equal(0, timer.alarms.length)
    # wait another few seconds until it goes off
    sleep 3
    assert_equal(1, timer.alarms.length)
  end
end