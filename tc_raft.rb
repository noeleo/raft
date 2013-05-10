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

    #TEST CASE 1: Make Sure Each Node starts off as a follower
    listOfServers = [p1, p2, p3, p4, p5]
    p1.sync_do do 
        puts p1.server_state.inspected
        assert_equal(p1.server_state.values[0][0], "follower")
    end

    

    # acks = p1.sync_callback(:kvput, [[1, :joe, 1, :hellerstein]], :kv_acks)
    # assert_equal([[1]], acks)

    p1.stop
    p2.stop
    p3.stop
    p4.stop
    p5.stop
  end
end

