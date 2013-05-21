require 'rubygems'
require 'bud'
require 'test/unit'

require 'vote_counter'

class RealVoteCounter
  include Bud
  include VoteCounter

  state do
    table :wins, [:time, :term]
  end

  bloom do
    wins <= race_won {|a| [budtime, a.term]}
  end
end

class TestVoteCounter < Test::Unit::TestCase
  def setup
    @vc = RealVoteCounter.new
    @vc.run_bg
  end
  
  def teardown
    @vc.stop
  end
  
  def test_simple_vote
    @vc.sync_do { @vc.setup <+ [[5]] }
    @vc.tick
    @vc.sync_do { @vc.vote <+ [[1, 'Bob', true], [1, 'Steve', true]] }
    @vc.sync_do { @vc.count_votes <+ [[1]] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [[1, 'George', true]] }
    @vc.sync_do { @vc.count_votes <+ [[1]] }
    assert_equal(1, @vc.wins.count)
  end
end
