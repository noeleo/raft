require 'rubygems'
require 'bud'

require 'time'

module SnoozeTimerProtocol
  state do
    # time_out is in milliseconds
    interface :input, :set_alarm, [] => [:time_out]
    interface :output, :alarm, [] => [:time_out]
  end
end

module SnoozeTimer
  include SnoozeTimerProtocol

  state do
    table :timer_state, [] => [:start_time, :time_out]
    scratch :buffer, timer_state.schema
    periodic :timer, 0.1
  end

  bloom do
    buffer <= (timer_state * timer).pairs do |s, t|
      s if (t.val.to_f - s.start_time) > (s.time_out.to_f/1000)
    end
    alarm <= buffer {|b| [b.time_out]}
    timer_state <- buffer
    # not sure if this is good form for Bud, but setting current time this way is best
    timer_state <+- set_alarm {|a| [Time.new.to_f, a.time_out]}
  end
end
