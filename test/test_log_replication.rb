require 'test/raft_tester'
require 'test/util/log'

class TestLogReplication < RaftTester
  
  def test_replicate_single_log
    start_servers(5)
    sleep 3
    # a leader should have been chosen
    all_states = []
    @servers.each do |s|
      s.states.values.each do |vals|
        all_states << vals[0]
      end
    end
    assert all_states.any?{|st| st == "leader"}
    # find the leader
    leader = @servers.select {|s| get_state(s) == 'leader'}.first
    assert leader != nil
    # send the leader a log and make sure it gets replicated
    leader.send_command <~ [[leader.ip_port, 'me', 'add']]
    sleep 1
    @servers.each do |s|
      puts "#{@servers.index(s)} and #{s.logger.logs.inspected} ok"
    end
  end
end
