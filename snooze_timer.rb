require 'rubygems'
require 'bud'
require 'time'

# Progress Timer works by setting an alarm with a timeout via the set_alarm input 
# interface and having it go off via the alarm output. If another set_alarm is
# issued before the current alarm goes off, the alarm will be reset. There is only
# a single timer.

module SnoozeTimerProtocol
  state do
    interface :input, :set_alarm, [] => [:time_out]
    interface :output, :alarm, [] => [:time_out]
  end
end

module SnoozeTimer
  include SnoozeTimerProtocol

  state do
    table :timer_state, [] => [:start_time, :time_out]
    # had to change buffer to this schema from set_alarm.schema because we were getting
    # duplicate keys... have no idea why
    table :buffer, [:start_time] => [:time_out]
    scratch :cyc, [:start_time, :time_out]
    scratch :single_cyc, cyc.schema
    periodic :timer, 0.001
  end

  bloom do
    buffer <= set_alarm
    cyc <= (buffer * timer).pairs {|b, t| [t.val.to_f, b.time_out]}
    # have to do a max on this because timer may have multiple elements for some reason
    # and we only want a single row
    single_cyc <= cyc.argagg(:choose, [], :start_time)
    timer_state <+- single_cyc {|c| [c.start_time, c.time_out]}
    buffer <- cyc {|c| [c.start_time, c.time_out]}

    # set off the alarm if the current time is time_out past the start_time
    alarm <= (timer_state * timer).pairs do |s, t|
      [s.time_out] if t.val.to_f - s.start_time > (s.time_out.to_f/1000.0)
    end

    # remove the alarm once it goes off
    timer_state <- (timer_state * alarm).lefts
  end
end