require 'test/raft_tester'
require 'test/util/log'

class TestRaft < RaftTester
  def get_reply(server, index)
    replies = server.replies.to_a
    replies = replies.sort_by {|r| r[0]}
    return [replies[index-1][1], replies[index-1][2]]
  end
  
  def test_return_true_leader
    start_servers(5)
    sleep 5
    leader = @servers.select {|s| get_state(s) == 'leader'}.first
    assert leader != nil
    # ask a non-leader to issue a command, should reply with actual leader
    leader_index = @servers.index(leader)
    follower_index = ((0..4).to_a - [leader_index])[rand(4)]
    follower = @servers[follower_index]
    follower.sync_do { follower.send_command <+ [['a']]}
    sleep 1
    assert_equal 1, follower.replies.count
    assert_equal [nil, leader.ip_port], get_reply(follower, 1)
  end
  
  def test_return_machine_result
    start_servers(5)
    sleep 5
    leader = @servers.select {|s| get_state(s) == 'leader'}.first
    assert leader != nil
    # ask the leader and should give back an answer after commit!
    leader.sync_do { leader.send_command <+ [['a']]}
    sleep 2
    assert_equal 1, leader.replies.count
    assert_equal ['a', nil], get_reply(leader, 1)
    leader_logs = Logs.new leader.logger.logs
    assert leader_logs.contains_index(1)
    assert_equal 'a', leader_logs.index(1).entry
    assert leader_logs.index(1).is_committed
    @servers.each do |s|
      assert leader_logs == Logs.new(s.logger.logs)
    end
  end
end
