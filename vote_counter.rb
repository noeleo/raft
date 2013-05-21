require 'rubygems'
require 'bud'

module VoteCounterProtocol
  state do
    interface :input, :setup, [] => [:num_voters]
    interface :input, :count_votes, [] => [:term]
    interface :input, :vote, [:term, :candidate] => [:is_granted]
    interface :output, :race_won, [:term]
  end
end

module VoteCounter
  include VoteCounterProtocol

  state do
    table :config, setup.schema
    table :voted, [:term, :candidate]
    table :yes_votes, [:term, :candidate]
    scratch :yes_votes_granted_in_current_term, [:candidate]
  end

  bloom :configure do
    config <= setup
  end
  
  bloom do
    voted <= vote {|v| [v.term, v.candidate]}
    yes_votes <= vote {|v| [v.term, v.candidate] if v.is_granted}
    yes_votes_granted_in_current_term <= (yes_votes * count_votes).pairs(:term => :term) do |v, t|
      [v.candidate]
    end
    # if we have majority, then we won!
    race_won <= (config * count_votes).pairs do |c, t|
      [t.term] if yes_votes_granted_in_current_term.count > (c.num_voters/2)
    end
  end
end
