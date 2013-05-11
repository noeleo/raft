require 'rubygems'
require 'bud'
require 'time'

module ProgressTimerProtocol
  state do
    interface :input, :set_alarm, [] => [:time_out]
    interface :output, :alarm, [] => [:time_out]
  end
end

module ProgressTimer
  include ProgressTimerProtocol

  state do
    table :timer_state, [] => [:start_tm, :time_out]
    table :buffer, set_alarm.schema
    scratch :cyc, timer_state.schema
    periodic :timer, 0.001
  end

  bloom do
    buffer <= set_alarm
    cyc <= (buffer * timer).pairs {|b, t| [t.val.to_f, b.time_out]}
    timer_state <+- cyc
    buffer <- cyc {|c| [c.time_out]}

    alarm <= (timer_state * timer).pairs do |s, t|
      [s.time_out] if t.val.to_f - s.start_tm > (s.time_out.to_f/1000.0)
    end

    timer_state <- (timer_state * alarm).lefts
  end
end