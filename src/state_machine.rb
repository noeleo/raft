module StateMachineProtocol
  state do
    interface :input, :execute, [:index] => [:command]
    interface :output, :result, [] => [:index, :result]
  end
end

# simple echo state machine
module StateMachine
  include StateMachineProtocol
  
  state do
    table :queue, execute.schema
  end
  
  bloom do
    queue <= execute
    temp :to_execute <= queue.argmin([], :index)
    queue <- to_execute
    result <= to_execute
  end
end
