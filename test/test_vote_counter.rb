require 'rubygems'
require 'bud'
require 'test/unit'

require 'vote_counter'

class RealVoteCounter
  include Bud
  include VoteCounter

  state do
    table :wins, [:time, :race]
  end

  bloom do
    wins <= race_won {|a| [budtime, a.race]}
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
    @vc.sync_do { @vc.vote <+ [['President', 'Bob', true], ['President', 'Steve', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President']] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['President', 'George', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President']] }
    assert_equal(1, @vc.wins.count)
  end
  
  def test_negative_votes
    @vc.sync_do { @vc.setup <+ [[5]] }
    @vc.tick
    @vc.sync_do { @vc.vote <+ [['President', 'Bob', false], ['President', 'Steve', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President']] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['President', 'George', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President']] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['President', 'Landon', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President']] }
    assert_equal(1, @vc.wins.count)
  end
  
  def test_multiple_races
    @vc.sync_do { @vc.setup <+ [[5]] }
    @vc.tick
    @vc.sync_do { @vc.vote <+ [['President', 'Bob', true], ['Senator', 'Steve', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President'], ['Senator']] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['President', 'George', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President'], ['Senator']] }
    assert_equal(0, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['President', 'Steve', true]] }
    @vc.sync_do { @vc.count_votes <+ [['President'], ['Senator']] }
    assert_equal(1, @vc.wins.count)
    @vc.sync_do { @vc.vote <+ [['Senator', 'Bro', true], ['Senator', 'Pro', true]] }
    @vc.sync_do { @vc.count_votes <+ [['Senator']] }
    assert_equal(2, @vc.wins.count)
  end
end
