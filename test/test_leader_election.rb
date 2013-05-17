require 'rubygems'
require 'bud'
require 'test/unit'
require 'raft'

require 'server_state'

class RealRaft
  include Bud
  include Raft

  state do
    table :states, [:timestamp] => [:state, :term]
    scratch :alarm_went_off, st.alarm.schema
  end

  bloom do
    states <= (st.current_state * st.current_term).pairs {|s, t| [budtime, s.state, t.term]}
    #stdio <~ st.current_state.inspected
  end
end

class TestLeaderElection < Test::Unit::TestCase
  def teardown
    @servers.each {|s| s.stop} if @servers
  end
  
  # create a cluster of servers with addresses starting with localhost:54321
  def create_cluster(num_servers)
    cluster = []
    (1..num_servers).to_a.each do |num|
      cluster << ["127.0.0.1:#{54320+num}"]
    end
    return cluster
  end
  
  def start_servers(num_servers, options = {})
    cluster = create_cluster(num_servers)
    @servers = []
    (1..num_servers).to_a.each do |num|
      instance = RealRaft.new(:port => 54320 + num)
      instance.set_cluster(cluster)
      instance.set_timeout(options[:time_out][0], options[:time_out][1]) if options[:time_out]
      instance.run_bg
      @servers << instance
    end
  end
  
  def get_state(server)
    server.st.current_state.values[0][0]
  end

  def get_term(server)
    server.st.current_term.values[0][0]
  end
  
  def get_states(server)
    server.states.values.map {|v| v[0]}
  end

  def test_start_off_as_follower
    start_servers(1)
    server = @servers.first
    # immediately check whether Raft instance starts as follower
    assert get_state(server) == 'follower'
  end

  def test_revert_to_follower
    start_servers(1, :time_out => [1000, 1000])
    server = @servers.first
    # server should increment term after a second, and transition from candidate to leader quickly
    sleep 1.5
    assert_equal 2, get_term(server)
    assert get_states(server).include?('candidate')
    assert_equal 'leader', get_state(server)
    # send RPC with higher term to server
    server.append_entries_request <~ [['127.0.0.1:54321', '127.0.0.1:54322', 10, 0, 0, 0, 0]]
    sleep 0.5
    # server should now have updated its term and reverted to follower state
    assert_equal 10, get_term(server)
    assert_equal 'follower', get_state(server)
  end

  def test_single_leader_elected
    start_servers(5)
    sleep 5
    all_states = []
    @servers.each do |s|
      s.states.values.each do |vals|
        all_states << vals[0]
      end
    end
    # a leader should have been chosen
    assert all_states.any?{|st| st == "leader"}
    # a single leader should have been chosen and converged
    assert @servers.map {|s| get_state(s) }.select {|str| str == 'leader'}.count == 1
  end

  def test_leader_going_offline_election_occurs
    start_servers(5)
    sleep 5
    leaderServer = @servers.select{|s| get_state(s) == 'leader'}.first
    assert leaderServer != nil
    leaderServer.stop
    @servers.delete(leaderServer)
    #are there any more leaders
    assert_equal(0, @servers.map{|s| get_state(s)}.select{|state| state == 'leader'}.count)
    assert_equal(4, @servers.count)
    #we have killed the server now, check to see if another election occurs
    sleep 5
    assert_equal(1,@servers.map{|s| get_state(s)}.select{|state| state == 'leader'}.count)
  end
  
  def test_tie_for_leader
    start_servers(2)
    sleep 5
    assert_equal(1,@servers.map{|s| get_state(s)}.select{|state| state == 'leader'}.count)
  end

  def test_term_increments_with_election
    start_servers(5)
    sleep 5 
    oldTerm =  get_term(@servers.first)
    assert_equal(1,@servers.map{|s| get_state(s)}.select{|state| state == 'leader'}.count)
    # kill the leader and force another election
    leaderServer = @servers.select{|s| get_state(s) == 'leader'}.first
    leaderServer.stop
    @servers.delete(leaderServer)
    # make sure there are no leaders and 1 server less in cluster
    assert_equal(0, @servers.map{|s| get_state(s)}.select{|state| state == 'leader'}.count)
    assert_equal(4, @servers.count)
    # start another election
    sleep 5
    newTerm = get_term(@servers.first)
    # check to see if old term is less than new term
    assert newTerm > oldTerm
  end

    ## TEST : if a follower receives an RPC with term greater than its own, it increments its term to received term
    ## find a follower:
    #follower = @servers.select {|s| s.current_state.values[0].first == 'leader'}.first
    #follower_term = follower.current_term.values[0].first
    ##send follower a vote request with term greater than its term
    #  # request_vote_request:
    #  # [:@dest, :from, :term, :last_log_index, :last_log_term]
    ##follower.sync_do {|s| s.request_vote_request <~ [[ip_port, ip_port, follower_term + 1, 1234, :last_log_term]] }
    ##(1..5).each { follower.sync_do }
    ## now test that follower incremented its term appropriately
    ##assert follower.current_term.values[0].first == follower_term + 1
end

