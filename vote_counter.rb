require 'rubygems'
require 'bud'

module VoteCounterProtocol
  state do
    interface :input, :vote, [:term, :candidate]
    interface :output, :end_election, [:term] => [:winner]
  end
end

module VoteCounter
  include VoteCounterProtocol
  import SnoozeTimer => :timer

  state do
    table :voted_for, [:term] => [:candidate]
    scratch :voted_for_in_current_term, [] => [:candidate]
    scratch :voted_for_in_current_step, [] => [:candidate]
    # keep record of all votes
    table :votes, [:term, :from] => [:is_granted]
    scratch :votes_granted_in_current_term, [:from]
    scratch :request_vote_term_max, current_term.schema
  end

  bloom do
  end
end
