require 'src/snooze_timer'

module ServerStateProtocol
  state do
    interface :input, :set_state, [:state]
    interface :input, :set_term, [:term]
    interface :input, :set_leader, [:leader]
    interface :input, :reset_timer, [:time_out]
    interface :output, :alarm, [] => [:time_out]
  end
end

module ServerState
  include ServerStateProtocol
  import SnoozeTimer => :timer

  # states in order of "importance"
  STATES = ['leader', 'candidate', 'follower']

  state do
    table :current_state, [] => [:state]
    table :current_term, [] => [:term]
    table :current_leader, [] => [:leader]
  end

  bootstrap do
    current_term <= [[1]]
    current_state <= [['follower']]
    current_leader <= [[nil]]
  end

  bloom :manage_state do
    temp :reordered <= set_state do |s|
      [STATES.index(s.state)]
    end
    temp :final_state <= reordered.argagg(:min, [], :state)
    current_state <+- final_state do |s|
      [STATES[s.state]]
    end
  end

  bloom :manage_term do
    temp :final_term <= set_term.argagg(:max, [], :term)
    current_term <+- (final_term * current_term).pairs do |f, c|
      [f.term] if f.term > c.term
    end
  end
  
  bloom :manage_leader do
    temp :final_leader <= set_leader.argagg(:max, [], :leader)
    current_leader <+- final_leader {|f| [f.leader]}
  end
  
  bloom :manage_timer do
    # reset timer
    temp :final_timer <= reset_timer.argagg(:choose, [], :time_out)
    timer.set_alarm <= final_timer {|t| [t.time_out]}
    # set off alarm
    alarm <= timer.alarm {|t| [t.time_out]}
  end
end
