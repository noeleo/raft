require 'rubygems'
require 'bud'
require 'time'

module ProgressTimerProtocol
  state do
    interface :input, :set_alarm, [:time_out]
    interface :output, :alarm, [:time_out]
  end
end

module ProgressTimer
  include ProgressTimerProtocol

  state do
    table :timer_state, [] => [:start_tm, :time_out]
    table :buffer, set_alarm.schema
    periodic :timer, 0.001
  end

  bloom :timer_logic do
    buffer <= set_alarm
    temp :cyc <= (buffer * timer)
    stdio <~ set_alarm.inspected
    stdio <~ buffer.inspected
    stdio <~ cyc.inspected
    timer_state <+- cyc.map {|s, t| [t.val.to_f, s.time_out]}
    buffer <- cyc.map{|s, t| s}

    alarm <= (timer_state * timer).map do |s, t|
      [s.time_out] if t.val.to_f - s.start_tm > (s.time_out.to_f/1000.0)
    end

    timer_state <- (timer_state * alarm).lefts
  end
end