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

  bootstrap do
    server_state <= [['follower']]
  end

  state do
    interface :input, :set_server_state, [:state]
    table :server_state, [] => [:state]
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
end