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
    states <= (current_state * current_term).pairs {|s, t| [budtime, s.state, t.term]}
    #stdio <~ current_state.inspected
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
    server = RealRaft.new(:port => 54320)
    server.run_bg
    # immediately check whether Raft instance starts as follower
    assert server.current_state.values[0].first == 'follower'
    server.stop
  end

#  def test_revert_to_follower
#    server = RealRaft.new(:port => 54320)
#    server.run_bg
#    sleep 1
#    # server should now be a candidate, term should be 2
#    assert server.current_state.values[0].first == 'candidate'
#    assert server.current_term.values[0].first == 2
#    # send RPC with higher term to server
#    server.append_entries_request <~ [['127.0.0.1:54320', '127.0.0.1:54321', 10, 0, 0, 0, 0]]
#    sleep 3
#    # server should now have updated its term and reverted to follower state
#    puts "term: #{server.current_state.values[0].first}"
#    assert server.current_state.values[0].first == 'follower'
#    assert server.current_term.values[0].first == 10
#    server.stop
#  end

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
    assert servers.map {|s| s.current_state.values[0].first }.select {|str| str == 'leader'}.count == 1
    # if we kill the leader, then a new one should be elected
    leader_index = servers.map {|s| s.current_state.values[0].first }.index('leader')
    servers[leader_index].stop
    sleep 5
    # TODO: finish the above test
    # remove the other leader from the list and make sure another takes leader
    servers.each {|s| s.stop}
  end

  def test_leader_going_offline_election_occurs
    cluster = create_cluster(5)
    listOfServers = []
    (1..5).to_a.each do |num|
      instance = RealRaft.new(:port => 54320 + num)
      instance.set_cluster(cluster)
      instance.run_bg
      listOfServers << instance
    end
    sleep 5
    leaderServer = listOfServers.select{|s| s.current_state.values[0].first == 'leader'}.first
    leaderServer.stop
    listOfServers.delete(leaderServer)
    #are there any more leaders
    assert_equal(0, listOfServers.map{|s|s.current_state.values[0].first}.select{|state| state == 'leader'}.count)
    assert_equal(4, listOfServers.count)
    #we have killed the server now, check to see if another election occurs
    (1..10).each {listOfServers.each{|serv| serv.sync_do} }
    sleep 5
    assert_equal(1,listOfServers.map{|s|s.current_state.values[0].first}.select{|state| state == 'leader'}.count)
    listOfServers << leaderServer
    assert_equal(5, listOfServers.count)
    listOfServers.each {|s| s.stop}
  end

    ## TEST : if a follower receives an RPC with term greater than its own, it increments its term to received term
    ## find a follower:
    #follower = listOfServers.select {|s| s.current_state.values[0].first == 'leader'}.first
    #follower_term = follower.current_term.values[0].first
    ##send follower a vote request with term greater than its term
    #  # request_vote_request:
    #  # [:@dest, :from, :term, :last_log_index, :last_log_term]
    ##follower.sync_do {|s| s.request_vote_request <~ [[ip_port, ip_port, follower_term + 1, 1234, :last_log_term]] }
    ##(1..5).each { follower.sync_do }
    ## now test that follower incremented its term appropriately
    ##assert follower.current_term.values[0].first == follower_term + 1
end

