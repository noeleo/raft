require 'rubygems'
require 'bud'
require 'test/unit'
require 'pry'

require 'raft'

# run with
# ruby -I/[path to raft directory] -I. test/test_raft.rb

class RealRaft
  include Bud
  include Raft

  state do
    table :states, [:timestamp] => [:state, :term]
  end

  bloom do
    states <= (server_state * current_term).pairs {|s, t| [budtime, s.state, t.term]}
    stdio <~ server_state.inspected
    #stdio <~ votes do |v|
    #    [v.term, v.from, v.is_granted] if v.from == ip_port
    #end
  end
end

class TestRaft < Test::Unit::TestCase

  # create a cluster of servers with addresses starting with localhost:54321
  def create_cluster(num_servers)
    cluster = []
    (1..num_servers).to_a.each do |num|
      cluster << ["127.0.0.1:#{54320+num}"]
    end
    return cluster
  end

  def test_start_off_as_follower
  end

  def test_single_leader_elected
    cluster = create_cluster(5)
    servers = []
    (1..5).to_a.each do |num|
      instance = RealRaft.new(:port => 54320 + num)
      instance.set_cluster(cluster)
      instance.run_bg
      servers << instance
    end
    sleep 5
    all_states = []
    servers.each do |s|
      s.states.values.each do |vals|
        all_states << vals[0]
      end
    end
    # a leader should have been chosen
    assert all_states.any?{|st| st == "leader"}
    # a single leader should have been chosen and converged
    assert servers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1
    # if we kill the leader, then a new one should be elected
    leader_index = servers.map {|s| s.server_state.values[0].first }.index('leader')
    servers[leader].stop
    sleep 5
    # TODO: finish the above test
    servers.each {|s| s.stop}
  end
    ## TEST : test that when a leader goes offline, a new leader is elected
    ## find and stop the current leader:
    #leader = listOfServers.select {|s| s.server_state.values[0].first == 'leader'}.first
    #leader.stop
    #listOfServers.delete(leader) # remove stopped server from listOfServers
    #(1..10).each { listOfServers.each {|s| s.sync_do } }
    ## now test that there is exactly one leader
    ##assert listOfServers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1
    ##assert_equal(arrayOfStates.count('leader'),1)
    ## CLEAN UP: add leader back to listOfServers
    #listOfServers << leader
    ## TEST : if a follower receives an RPC with term greater than its own, it increments its term to received term
    ## find a follower:
    #follower = listOfServers.select {|s| s.server_state.values[0].first == 'leader'}.first
    #follower_term = follower.current_term.values[0].first
    ##send follower a vote request with term greater than its term
    #  # request_vote_request:
    #  # [:@dest, :from, :term, :last_log_index, :last_log_term]
    ##follower.sync_do {|s| s.request_vote_request <~ [[ip_port, ip_port, follower_term + 1, 1234, :last_log_term]] }
    ##(1..5).each { follower.sync_do }
    ## now test that follower incremented its term appropriately
    ##assert follower.current_term.values[0].first == follower_term + 1
end

