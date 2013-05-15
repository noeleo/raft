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
    table :terms, [:time] => [:term]
    table :alarms, [:time] => [:time_out]
  end

  bloom do
    states <= current_state {|s| [budtime, s.state]}
    terms <= current_term {|s| [budtime, s.term]}
    alarms <= alarm {|a| [budtime, a.time_out]}
  end
end

class TestServerState < Test::Unit::TestCase
  def get_state(server)
    server.current_state.values[0][0]
  end

  def get_term(server)
    server.current_term.values[0][0]
  end

  def test_one_server_state
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.set_state <+ [['candidate']] }
    # have to tick it since the server state should change on the next tick
    server.tick
    # length should be 3: 1st is bootstrap, then sync, then update
    assert_equal(3, server.states.length)
    assert_equal('candidate', get_state(server))
  end

  def test_tie_breaking
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.set_state <+ [['candidate'], ['leader'], ['follower']]}
    server.tick
    assert_equal(3, server.states.length)
    assert_equal('follower', get_state(server))
  end

  def test_duplicate_states
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.set_state <+ [['candidate'], ['leader'], ['leader']]}
    server.tick
    assert_equal(3, server.states.length)
    assert_equal('candidate', get_state(server))
  end

  def test_multiple_calls
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.set_state <+ [['leader'], ['leader']]}
    # this will tick it so don't need to tick here
    server.sync_do { server.set_state <+ [['follower'], ['candidate']]}
    assert_equal(3, server.states.length)
    assert_equal('leader', get_state(server))
    # now tick for the other delay to come in
    server.tick
    assert_equal(4, server.states.length)
    assert_equal('follower', get_state(server))
  end

  def test_update_term
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.set_term <+ [[3], [2]]}
    server.tick
    assert_equal(3, server.terms.length)
    # should have taken the max
    assert_equal(3, get_term(server))
  end
  
  def test_alarm
    server = RealServerState.new
    server.run_bg
    server.sync_do { server.reset_timer <+ [[true]]}
    server.tick
    sleep 0.2
    assert_equal(0, server.alarms.length)
    sleep 1
    assert_equal(1, server.alarms.length)
  end
end
