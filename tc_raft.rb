require 'rubygems'
require 'bud'
require 'test/unit'
require 'raft'
require 'pry'

class TestRaft < Test::Unit::TestCase
  class RaftBloom
    include Bud
    include Raft 
  end

  def test_raft
    p1 = RaftBloom.new(:port=>54321)
    p1.run_bg

    p2 = RaftBloom.new(:port=>54322)
    p2.run_bg

    p3 = RaftBloom.new(:port=>54323)
    p3.run_bg

    p4 = RaftBloom.new(:port=>54324)
    p4.run_bg

    p5 = RaftBloom.new(:port=>54325)
    p5.run_bg

    p6 = RaftBloom.new(:port=>54326)
    p6.run_bg


    #TEST CASE 1: Make Sure Each Node starts off as a follower
    listOfServers = [p1, p2, p3, p4, p5]
    listOfServers.each do |server|
      server.sync_do do 
        assert_equal(server.server_state.values[0], ["follower"])
      end
    end

    # TEST 2: test that a leader is initially elected
    # tick servers and assume normal operation
    (1..10).each { 
      listOfServers.each {|s| s.sync_do } 
    }
    assert listOfServers.map {|s| s.server_state.values[0].first }.any? {|str| str == 'leader'}

    # TEST 3: test that there is exactly one leader
    assert listOfServers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1

    # TEST 4: test that when a leader goes offline, a new leader is elected
    # find and stop the current leader:
    leader = listOfServers.select {|s| s.server_state.values[0].first == 'leader'}.first
    leader.stop
    listOfServers.delete(leader) # remove stopped server from listOfServers
    (1..10).each { listOfServers.each {|s| s.sync_do } }
    # now test that there is exactly one leader
    assert listOfServers.map {|s| s.server_state.values[0].first }.select {|str| str == 'leader'}.count == 1

    p1.stop
    p2.stop
    p3.stop
    p4.stop
    p5.stop
    p6.stop
  end
end

