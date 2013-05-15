require 'rubygems'
require 'bud'

module LeaderElectionProtocol
  state do
    interface :input, :set_members, [:host]
    interface :input, :begin_election, [:term] => [:last_log_index, :last_log_term]
    interface :output, :finish_election, [:term] => [:leader]
  end
end

module LeaderElection
  include LeaderElectionProtocol
  
  def random_timeout
    TIMEOUT_MIN + rand(TIMEOUT_MAX-TIMEOUT_MIN)
  end
  
  state do
    channel :vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :vote_response, [:@dest, :from, :term, :is_granted]
    
    
  end
end
