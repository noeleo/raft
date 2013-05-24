require 'test/raft_tester'
require 'test/util/log'

class TestLogReplication < RaftTester
  
  def test_replicate_single_log
    start_servers(5)
    sleep 5
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
    sleep 2
    leader_logs = Logs.new leader.logger.logs
    assert leader_logs.contains_index(1)
    assert_equal 'add', leader_logs.index(1).entry
    assert leader_logs.index(1).is_committed
    @servers.each do |s|
      assert leader_logs == Logs.new(s.logger.logs)
    end
  end
  
  def test_majority_servers_down
    start_servers(5)
    sleep 5
    leader = @servers.select {|s| get_state(s) == 'leader'}.first
    assert leader != nil
    # remove 3 servers and issue a command that should not be committed
    leader_index = @servers.index(leader)
    stopped = []
    (0..2).each do |num|
      s = (num == leader_index) ? @servers[3] : @servers[num]
      s.stop
      stopped << s
    end
    stopped.each {|s| @servers.delete(s)}
    leader.send_command <~ [[leader.ip_port, 'me', 'add']]
    sleep 2
    leader_logs = Logs.new leader.logger.logs
    assert leader_logs.contains_index(1)
    assert (not leader_logs.index(1).is_committed)
    @servers.each do |s|
      assert leader_logs == Logs.new(s.logger.logs)
    end
  end
  
  def test_remove_conflicting_logs
    start_servers(5)
    sleep 5
    leader = @servers.select {|s| get_state(s) == 'leader'}.first
    assert leader != nil
    leader_index = @servers.index(leader)
    # put in some entries into a follower
    bad_server_index = ((0..4).to_a - [leader_index])[rand(4)]
    bad_server = @servers[bad_server_index]
    bad_server.sync_do { bad_server.logger.add_log <+ [[-1, 'bad entry']]}
    sleep 0.5
    bad_server.sync_do { bad_server.logger.add_log <+ [[-1, 'another bad entry']]}
    sleep 0.5
    bad_logs = Logs.new bad_server.logger.logs
    assert bad_logs.contains_index(1)
    assert_equal -1, bad_logs.index(1).term
    assert_equal 'bad entry', bad_logs.index(1).entry
    assert bad_logs.contains_index(2)
    assert_equal -1, bad_logs.index(2).term
    assert_equal 'another bad entry', bad_logs.index(2).entry
    assert_equal 3, bad_server.logger.logs.count
    assert_equal 1, leader.logger.logs.count
    # now add an entry to the leader and make sure the bad server updates itself
    leader.send_command <~ [[leader.ip_port, 'me', 'good entry']]
    sleep 2
    leader_logs = Logs.new leader.logger.logs
    @servers.each do |s|
      assert leader_logs == Logs.new(s.logger.logs)
    end
  end
end
