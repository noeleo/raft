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
    states <= (server_state * current_term).pairs  do |s, t| [budtime, s.state, t.term] end
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

  def test_raft
    cluster = create_cluster(5)
    p1 = RealRaft.new(:port=>54321)
    p1.set_cluster(cluster)
    p1.run_bg

    p2 = RealRaft.new(:port=>54322)
    p2.set_cluster(cluster)
    p2.run_bg

    p3 = RealRaft.new(:port=>54323)
    p3.set_cluster(cluster)
    p3.run_bg

    p4 = RealRaft.new(:port=>54324)
    p4.set_cluster(cluster)
    p4.run_bg

    p5 = RealRaft.new(:port=>54325)
    p5.set_cluster(cluster)
    p5.run_bg


    # TODO: you should put these test cases in different methods named test_<test you are performing>
    # see all other test files for reference

    # TODO: tests are not being done correctly. LHS of assert_equal is the expected value and right side is the actual value


    #TEST CASE 1: Make Sure Each Node starts off as a follower
    # TODO: this is NOT going to work. it bootstraps by sending everyone messages and the whole process begins immediately
    listOfServers = [p1, p2, p3, p4, p5]
    listOfServers.each do |server|
      server.tick
      #server.sync_do do 
        #assert_equal(["follower"], server.server_state.values[0][0])
      #end
    end

    # TEST : test that a leader is initially elected
    # tick servers and assume normal operation
    (1..100).each {
      listOfServers.each {|s| s.sync_do } 
    }
    #puts p1.methods
    #listOfServers.map{|s| puts s.server_state.values[0]}
    #puts p1.state.inspected
    arrayOfStates = []
    listOfServers.map {|server| 
        server.states.values.map{ |vals|
            arrayOfStates <<  vals[0]
        }
    }
    assert arrayOfStates.any?{|str| str == "leader"}

    # TEST : test that there is exactly one leader
    assert listOfServers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1

    # TEST : test that when a leader goes offline, a new leader is elected
    # find and stop the current leader:
    leader = listOfServers.select {|s| s.server_state.values[0].first == 'leader'}.first
    leader.stop
    listOfServers.delete(leader) # remove stopped server from listOfServers
    (1..10).each { listOfServers.each {|s| s.sync_do } }

    # now test that there is exactly one leader
    #assert listOfServers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1
    #assert_equal(arrayOfStates.count('leader'),1)

    # CLEAN UP: add leader back to listOfServers
    listOfServers << leader

    # TEST : if a follower receives an RPC with term greater than its own, it increments its term to received term
    # find a follower:
    follower = listOfServers.select {|s| s.server_state.values[0].first == 'leader'}.first
    follower_term = follower.current_term.values[0].first

    #send follower a vote request with term greater than its term
      # request_vote_request:
      # [:@dest, :from, :term, :last_log_index, :last_log_term]
    #follower.sync_do {|s| s.request_vote_request <~ [[ip_port, ip_port, follower_term + 1, 1234, :last_log_term]] }
    #(1..5).each { follower.sync_do }
    # now test that follower incremented its term appropriately
    #assert follower.current_term.values[0].first == follower_term + 1

    p1.stop
    p2.stop
    p3.stop
    p4.stop
    p5.stop
  end
end

