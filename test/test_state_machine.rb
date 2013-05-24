require 'rubygems'
require 'bud'
require 'test/unit'

require 'src/state_machine'

class RealStateMachine
  include Bud
  include StateMachine

  state do
    table :results, [:time] => [:index, :result]
  end

  bloom do
    results <= result {|r| [budtime, r.index, r.result]}
  end
end

class TestStateMachine < Test::Unit::TestCase
  def setup
    @sm = RealStateMachine.new
    @sm.run_bg
  end
  
  def teardown
    @sm.stop
  end
  
  def get_result(index)
    results = @sm.results.to_a
    results = results.sort_by {|r| r[0]}
    return results[index-1][2]
  end
  
  def test_single_command_at_a_time
    @sm.sync_do { @sm.execute <+ [[1, 'cul']]}
    assert_equal 'cul', get_result(1)
    @sm.sync_do { @sm.execute <+ [[5, 'right']]}
    assert_equal 'right', get_result(2)
  end
  
  def test_multiple_commands
    @sm.sync_do { @sm.execute <+ [[7, 'seven'], [3, 'three'], [4, 'four']]}
    @sm.tick
    @sm.sync_do { @sm.execute <+ [[1, 'one']]}
    @sm.tick
    assert_equal 'three', get_result(1)
    assert_equal 'four', get_result(2)
    assert_equal 'one', get_result(3)
    assert_equal 'seven', get_result(4)
  end
end
