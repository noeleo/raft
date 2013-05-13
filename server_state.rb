require 'rubygems'
require 'bud'

module ServerStateProtocol
  state do
    interface :input, :set_server_state, [:state]
    interface :input, :set_term, [:term]
  end
end

module ServerState
  include ServerStateProtocol

  STATE_TO_ORDER = {
    'follower' =>  'a',
    'candidate' => 'b',
    'leader' =>    'c'
  }
  ORDER_TO_STATE = {
    'a' => 'follower',
    'b' => 'candidate',
    'c' => 'leader'
  }

  state do
    table :server_state, [] => [:state]
    table :current_term, [] => [:term]
  end

  bootstrap do
    current_term <= [[1]]
    server_state <= [['follower']]
  end

  bloom :manage_state do
    temp :reordered <= set_server_state do |s|
      [STATE_TO_ORDER[s.state]]
    end
    temp :final_state <= reordered.argagg(:min, [], :state)
    server_state <+- final_state do |s|
      [ORDER_TO_STATE[s.state]]
    end
  end

  bloom :set_term do
    temp :final_term <= set_term.argagg(:max, [], :term)
    current_term <+- (final_term * current_term).pairs do |f, c|
      [f.term] if f.term > c.term
    end
  end
end