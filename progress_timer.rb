require 'rubygems'
require 'bud'
require 'time'

# Progress Timer works by setting an alarm with a timeout via the set_alarm input 
# interface and having it go off via the alarm output. If another set_alarm is
# issued before the current alarm goes off, the alarm will be reset. There is only
# a single timer.

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
    scratch :cyc, [:start_tm, :time_out]
    scratch :single_cyc, cyc.schema
    periodic :timer, 0.001
  end

  bloom do
    buffer <= set_alarm
    cyc <= (buffer * timer).pairs {|b, t| [t.val.to_f, b.time_out]}
    single_cyc <= cyc.argagg(:max, [], :start_tm)
    timer_state <+- single_cyc {|c| [c.start_tm, c.time_out]}
    buffer <- cyc {|c| [c.time_out]}

    alarm <= (timer_state * timer).pairs do |s, t|
      [s.time_out] if t.val.to_f - s.start_tm > (s.time_out.to_f/1000.0)
    end

    timer_state <- (timer_state * alarm).lefts
  end
end