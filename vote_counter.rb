require 'rubygems'
require 'bud'

module VoteCounterProtocol
  state do
    interface :input, :setup, [] => [:num_voters]
    interface :input, :count_votes, [:race]
    interface :input, :vote, [:race, :candidate] => [:is_granted]
    interface :output, :race_won, [:race]
  end
end

module VoteCounter
  include VoteCounterProtocol

  state do
    table :config, setup.schema
    table :voted, [:race, :candidate]
    lmap :yes_votes
  end

  bloom :configure do
    config <= setup
  end
  
  bloom do
    voted <= vote {|v| [v.race, v.candidate]}
    yes_votes <= vote {|v| {v.race => Bud::SetLattice.new([v.candidate])} if v.is_granted}
    # if we have majority, then we won!
    race_won <= (config * count_votes).pairs do |c, v|
      yes_votes.at(v.race, Bud::SetLattice).size.gt(c.num_voters/2).when_true {[v.race]}
    end
  end
end
