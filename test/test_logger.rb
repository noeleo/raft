require 'rubygems'
require 'bud'
require 'test/unit'

require 'src/logger'

class RealLogger
  include Bud
  include Logger

  state do
    table :stati, [:time] => [:last_index, :last_term, :last_committed]
    table :added_indices, [:time] => [:index]
    table :time_commited_logs, [:time, :index] => [:entry]
  end

  bloom do
    stati <= status {|s| [budtime, s.last_index, s.last_term, s.last_committed]}
    added_indices <= added_log_index {|a| [budtime, a.index]}
    time_commited_logs <= committed_logs {|c| [budtime, c.index, c.entry]}
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
  
  def num_logs
    # forget about empty first one
    @logger.logs.count - 1
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
    @logger.sync_do { @logger.get_status <+ [[true]] }
    assert_equal index, last_index
    assert_equal term, last_term
    assert_equal committed, last_committed
  end
  
  def test_adding_and_committing_logs
    @logger.sync_do { @logger.add_log <+ [[1, 'eat']] }
    assert_status 1, 1, 0
    @logger.sync_do { @logger.add_log <+ [[1, 'code']]}
    @logger.sync_do { @logger.add_log <+ [[2, 'sleep']]}
    assert_status 3, 2, 0
    assert_equal 3, @logger.added_indices.count
    @logger.sync_do { @logger.commit_logs_before <+ [[2]]}
    assert_status 3, 2, 2
    assert_equal 2, @logger.time_commited_logs.count
    @logger.sync_do { @logger.add_log <+ [[6, 'cool']]}
    @logger.sync_do { @logger.commit_logs_before <+ [[4]]}
    assert_equal 4, @logger.time_commited_logs.count
    assert_status 4, 6, 4
    assert_equal 4, num_logs
  end
  
  def test_replacing_logs
    @logger.sync_do { @logger.add_log <+ [[1, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[1, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[7, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[8, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[9, 'eat']] }
    assert_status 5, 9, 0
    # replace log 3 with this and remove all elements after
    @logger.sync_do { @logger.add_log <+ [[5, 'sleep', 3]]}
    assert_status 3, 5, 0
    assert_equal 3, num_logs
  end
  
  def test_remove_uncommitted_logs
    @logger.sync_do { @logger.add_log <+ [[1, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[1, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[7, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[8, 'eat']] }
    @logger.sync_do { @logger.add_log <+ [[9, 'eat']] }
    @logger.sync_do { @logger.commit_logs_before <+ [[4]]}
    assert_status 5, 9, 4
    @logger.sync_do { @logger.remove_uncommitted_logs <+ [[true]]}
    assert_status 4, 8, 4
    assert_equal 4, num_logs
  end
end
