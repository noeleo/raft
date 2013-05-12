require 'rubygems'
require 'bud'

module ServerState

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
    interface :input, :possible_server_states, [:state]
    table :server_state, [] => [:state]
  end

  bloom :manage_state do
    stdio <~ possible_server_states.inspected
    temp :reordered <= possible_server_states do |s|
      [STATE_TO_ORDER[s.state]]
    end
    temp :final_state <= reordered.argagg(:min, [], :state)
    server_state <+- final_state do |s|
      [ORDER_TO_STATE[s.state]]
    end
  end
end