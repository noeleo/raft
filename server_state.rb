require 'rubygems'
require 'bud'

require 'snooze_timer'

module ServerStateProtocol
  state do
    interface :input, :set_state, [:state]
    interface :input, :set_term, [:term]
    interface :input, :reset_timer, [:time_out]
    interface :output, :alarm, [] => [:time_out]
  end
end

module ServerState
  include ServerStateProtocol
  import SnoozeTimer => :timer

  STATE_TO_ORDER = {
    'leader'    => 'a',
    'candidate' => 'b',
    'follower'  => 'c'
  }
  ORDER_TO_STATE = {
    'a' => 'leader',
    'b' => 'candidate',
    'c' => 'follower'
  }

  state do
    table :current_state, [] => [:state]
    table :current_term, [] => [:term]
  end

  bootstrap do
    current_term <= [[1]]
    current_state <= [['follower']]
  end

  bloom :manage_state do
    temp :reordered <= set_state do |s|
      [STATE_TO_ORDER[s.state]]
    end
    temp :final_state <= reordered.argagg(:min, [], :state)
    current_state <+- final_state do |s|
      [ORDER_TO_STATE[s.state]]
    end
  end

  bloom :manage_term do
    temp :final_term <= set_term.argagg(:max, [], :term)
    current_term <+- (final_term * current_term).pairs do |f, c|
      [f.term] if f.term > c.term
    end
  end
  
  bloom :manage_timer do
    # reset timer
    temp :final_timer <= reset_timer.argagg(:choose, [], :time_out)
    timer.set_alarm <= final_timer {|t| [t.time_out]}
    # set off alarm
    alarm <= timer.alarm {|t| [t.time_out]}
  end
end
