require 'rubygems'
require 'bud'
require 'test/unit'

require 'src/server_state'

class RealServerState
  include Bud
  include ServerState

  state do
    table :states, [:time] => [:state]
    table :terms, [:time] => [:term]
    table :leaders, [:time] => [:leader]
    table :alarms, [:time] => [:time_out]
  end

  bloom do
    states <= current_state {|s| [budtime, s.state]}
    terms <= current_term {|s| [budtime, s.term]}
    leaders <= current_leader {|s| [budtime, s.leader]}
    alarms <= alarm {|a| [budtime, a.time_out]}
  end
end

class TestServerState < Test::Unit::TestCase
  def setup
    @st = RealServerState.new
    @st.run_bg
  end
  
  def teardown
    @st.stop
  end
  
  def get_state
    @st.current_state.values[0][0]
  end

  def get_term
    @st.current_term.values[0][0]
  end

  def test_one_server_state
    @st.sync_do { @st.set_state <+ [['candidate']] }
    # have to tick it since the server state should change on the next tick
    @st.tick
    # length should be 3: 1st is bootstrap, then sync, then update
    assert_equal(3, @st.states.length)
    assert_equal('candidate', get_state)
  end

  def test_tie_breaking
    @st.sync_do { @st.set_state <+ [['candidate'], ['leader'], ['follower']]}
    @st.tick
    assert_equal(3, @st.states.length)
    assert_equal('leader', get_state)
  end

  def test_duplicate_states
    @st.sync_do { @st.set_state <+ [['candidate'], ['leader'], ['leader']]}
    @st.tick
    assert_equal(3, @st.states.length)
    assert_equal('leader', get_state)
  end

  def test_multiple_calls
    @st.sync_do { @st.set_state <+ [['leader'], ['leader']]}
    # this will tick it so don't need to tick here
    @st.sync_do { @st.set_state <+ [['follower'], ['candidate']]}
    assert_equal(3, @st.states.length)
    assert_equal('leader', get_state)
    # now tick for the other delay to come in
    @st.tick
    assert_equal(4, @st.states.length)
    assert_equal('candidate', get_state)
  end

  def test_update_term
    @st.sync_do { @st.set_term <+ [[3], [2]]}
    @st.tick
    assert_equal(3, @st.terms.length)
    # should have taken the max
    assert_equal(3, get_term)
  end
  
  def test_alarm
    @st.sync_do { @st.reset_timer <+ [[2000]]}
    @st.tick
    sleep 1
    assert_equal(0, @st.alarms.length)
    sleep 2
    assert_equal(1, @st.alarms.length)
  end
end
