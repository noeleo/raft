require 'rubygems'
require 'bud'
require 'test/unit'

require 'logger'

class RealLogger
  include Bud
  include Logger

  state do
    table :stati, [:time] => [:last_index, :last_term, :last_committed]
  end

  bloom do
    stati <= status {|s| [budtime, s.last_index, s.last_term, s.last_committed]}
  end
end

class TestLogger < Test::Unit::TestCase
  def setup
    @logger = RealLogger.new
    @logger.run_bg
  end
  
  def teardown
    @logger.stop
  end
  
  def last_index
    @logger.stati.values.last[0]
  end
  
  def last_term
    @logger.stati.values.last[1]
  end
  
  def last_committed
    @logger.stati.values.last[2]
  end
  
  def assert_status(index, term, committed)
    assert_equal index, last_index
    assert_equal term, last_term
    assert_equal committed, last_committed
  end
  
  def test_adding_and_committing_logs
    @logger.sync_do { @logger.add_log <+ [[1, 'eat', false]] }
    @logger.sync_do { @logger.get_status <+ [[true]] }
    assert_status 1, 1, 0
    @logger.sync_do { @logger.add_log <+ [[1, 'code', false]]}
    @logger.sync_do { @logger.add_log <+ [[2, 'sleep', false]]}
    @logger.sync_do { @logger.get_status <+ [[true]] }
    assert_status 3, 2, 0
    @logger.sync_do { @logger.commit_logs_before <+ [[2]]}
    @logger.sync_do { @logger.get_status <+ [[true]] }
    assert_status 3, 2, 2
    @logger.sync_do { @logger.add_log <+ [[6, 'cool', false]]}
    @logger.sync_do { @logger.commit_logs_before <+ [[4]]}
    @logger.sync_do { @logger.get_status <+ [[true]] }
    assert_status 4, 6, 4
  end
  
  def 
end
