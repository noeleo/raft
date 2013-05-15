require 'rubygems'
require 'bud'

module VoteCounterProtocol
  state do
    interface :input, :setup, [] => [:num_members]
    interface :input, :start_election, [] => [:term]
    interface :input, :vote, [:term, :candidate] => [:is_granted]
    interface :output, :election_won, [:term]
  end
end

module VoteCounter
  include VoteCounterProtocol

  state do
    table :config, setup.schema
    table :current_term, [] => [:term]
    table :voted, [:term, :candidate]
    table :yes_votes, [:term, :candidate]
    scratch :yes_votes_granted_in_current_term, [:candidate]
  end

  bloom :configure do
    config <= setup
    current_term <+- start_election
  end
  
  bloom do
    voted <= vote {|v| [v.term, v.candidate]}
    yes_votes <= vote {|v| [v.term, v.candidate] if v.is_granted}
    yes_votes_granted_in_current_term <= (yes_votes * current_term).pairs(:term => :term) do |v, t|
      [v.candidate]
    end
    # if we have majority, then we won!
    election_won <= (config * current_term).pairs do |c, t|
      [t.term] if yes_votes_granted_in_current_term.count > (c.num_members/2)
    end
  end
end
