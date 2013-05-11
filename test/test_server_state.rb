require 'rubygems'
require 'bud'
require 'test/unit'

require 'server_state'

# run with
# ruby -I/[path to raft directory] -I. test/test_server_state.rb

class RealServerState
  include Bud
  include ServerState

  state do
    table :states, [:time] => [:state]
  end

  bloom do
    states <= server_state {|s| [budtime, s.state]}
  end
end

class TestServerState < Test::Unit::TestCase
  def test_one_server_state
    state = RealServerState.new
    state.run_bg
    state.sync_do { state.possible_server_states <+ [['candidate']] }
    # have to tick it since the server state should change on the next tick
    state.tick
    assert_equal(1, state.states.length)
    assert_equal('candidate', state.states.first.state)
  end

  def test_tie_breaking
    state = RealServerState.new
    state.run_bg
    state.sync_do { state.possible_server_states <+ [['candidate'], ['leader'], ['follower']]}
    state.tick
    assert_equal(1, state.states.length)
    assert_equal('follower', state.states.first.state)
  end

  def test_duplicate_states
    state = RealServerState.new
    state.run_bg
    state.sync_do { state.possible_server_states <+ [['candidate'], ['leader'], ['leader']]}
    state.tick
    assert_equal(1, state.states.length)
    assert_equal('candidate', state.states.first.state)
  end

  def test_multiple_calls
    state = RealServerState.new
    state.run_bg
    state.sync_do { state.possible_server_states <+ [['leader'], ['leader']]}
    # this will tick it so don't need to tick here
    state.sync_do { state.possible_server_states <+ [['follower'], ['candidate']]}
    assert_equal(1, state.states.length)
    assert_equal('leader', state.states.first.state)
    # now tick for the other delay to come in
    state.tick
    assert_equal(2, state.states.length)
    assert_equal('follower', state.states.to_a[1].state)
  end
end