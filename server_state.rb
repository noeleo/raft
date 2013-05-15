require 'rubygems'
require 'bud'

require 'snooze_timer'

module ServerStateProtocol
  state do
    interface :input, :set_state, [:state]
    interface :input, :set_term, [:term]
    # reset should always be true
    interface :input, :reset_timer, [] => [:reset]
    interface :output, :alarm, [] => [:time_out]
  end
end

module ServerState
  include ServerStateProtocol
  import SnoozeTimer => :timer
  
  # set timeouts in milliseconds
  MIN_TIMEOUT = 300
  MAX_TIMEOUT = 800
  
  def random_timeout
    MIN_TIMEOUT + rand(MAX_TIMEOUT - MIN_TIMEOUT)
  end

  STATE_TO_ORDER = {
    'leader'    => 'a',
    'follower'  => 'c',
    'candidate' => 'b'
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
    temp :final_timer <= reset_timer.argagg(:choose, [], :reset)
    timer.set_alarm <= final_timer {|t| [random_timeout]}
    # set off alarm
    alarm <= timer.alarm {|t| [t.time_out]}
  end
end
