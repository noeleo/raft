require 'src/server_state'
require 'src/logger'
require 'src/vote_counter'
require 'src/state_machine'

module RaftProtocol
end

module Raft
  include RaftProtocol
  import ServerState => :st
  import Logger => :logger
  import VoteCounter => :election
  import VoteCounter => :commit
  import StateMachine => :machine

  def initialize(cluster, options = {})
    @HOSTS = cluster.map {|x| [x]}
    @MIN_TIMEOUT = 300
    @IS_TIMEOUT_RANDOM = true
    super(options)
  end
  
  def set_timeout(min_time, is_random = true)
    @MIN_TIMEOUT = min_time
    @IS_TIMEOUT_RANDOM = is_random
  end
  
  # a random timeout in range range between the min timeout and twice that
  def random_timeout
    @IS_TIMEOUT_RANDOM ? @MIN_TIMEOUT + rand(@MIN_TIMEOUT) : @MIN_TIMEOUT
  end
  
  state do
    # client communication
    #channel :send_command, [:@dest, :from, :command]
    #channel :reply_command, [:@dest, :response, :leader_redirect]
    interface :input, :send_command, [:command]
    interface :output, :reply_command, [:response, :leader_redirect]
    
    # RPCs
    channel :vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :vote_response, [:@dest, :from, :term, :is_granted]
    channel :append_entries_request, [:@dest, :from, :term, :prev_log_index, :prev_log_term, :entry, :commit_index]
    # also send back the index so that we know which request is being acked
    channel :append_entries_response, [:@dest, :from, :term, :index, :is_success]
    
    # clients: used for network communication
    #table :respond_to, [:index] => [:client]
    
    # leader election
    table :members, [:host]
    table :voted_for, [:term] => [:candidate]
    scratch :voted_for_in_current_term, [] => [:candidate]
    scratch :voted_for_in_current_step, [] => [:candidate]
    
    # log replication
    table :next_index, [:host] => [:index]
    scratch :preceding_logs, [:host] => [:index, :term]
    scratch :potential_candidates, vote_request.schema
    
    periodic :heartbeat, 0.1
  end

  bootstrap do
    members <= @HOSTS - [[ip_port]]
    next_index <= members {|m| [m.host, 1]}
    st.reset_timer <= [[random_timeout]]
    election.setup <= [[@HOSTS.count]]
    commit.setup <= [[@HOSTS.count]]
  end
  
  bloom :module_input do
    logger.get_status <= [[true]]
    election.count_votes <= st.current_term {|t| [t.term]}
    # count the votes of the next entry to be committed
    commit.count_votes <= logger.status {|l| [l.last_committed + 1]}
  end
  
  # this isn't fully accurate but will eventually be correct in stable operation
  bloom :determine_leader do
    st.set_leader <= st.current_state {|s| [ip_port] if s.state == 'leader'}
    st.set_leader <= append_entries_request {|a| [a.from]}
  end

  bloom :timeout do
    # increment current term
    st.set_term <= (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      [t.term + 1] if s.state != 'leader'
    end
    # transition to candidate state
    st.set_state <= (st.alarm * st.current_state).pairs do |a, s|
      ['candidate'] if s.state != 'leader'
    end
    # reset the timer
    st.reset_timer <= (st.alarm * st.current_state).pairs do |a, s|
      [random_timeout] if s.state != 'leader'
    end
    # vote for ourselves (have to do term + 1 because it hasn't been incremented yet)
    election.vote <= (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      [t.term + 1, ip_port, true] if s.state != 'leader'
    end
    voted_for <= (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      [t.term + 1, ip_port] if s.state != 'leader'
    end
    # remove all uncommitted logs
    logger.remove_uncommitted_logs <= (st.alarm * st.current_state).pairs do |a, s|
      [true] if s.state != 'leader'
    end
  end

  bloom :send_vote_requests do
    vote_request <~ (heartbeat * members * st.current_state * st.current_term).combos do |h, m, s, t|
      [m.host, ip_port, t.term, 0, 0] if s.state == 'candidate' and not election.voted.include?([t.term, m.host])
    end
  end

  bloom :candidate_operation do
    # if we discover our term is stale, step down to follower and update our term
    st.set_state <= (st.current_state * vote_response * st.current_term).combos do |s, v, t|
      ['follower'] if (s.state == 'candidate' or s.state == 'leader') and v.term > t.term
    end
    st.set_term <= vote_response.argmax([], :term) {|v| [v.term]}
    # record votes if we are in the correct term
    election.vote <= (st.current_state * vote_response * st.current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term
    end
    # if we won the election, then we become leader
    st.set_state <= (election.race_won * st.current_state * st.current_term).combos do |e, s, t|
      ['leader'] if s.state == 'candidate' and e.race == t.term
    end
  end

  bloom :cast_votes do
    # if we discover our term is stale, step down to follower and update our term
    st.set_state <= (st.current_state * vote_request * st.current_term).combos do |s, v, t|
      ['follower'] if (s.state == 'candidate' or s.state == 'leader') and v.term > t.term
    end
    st.set_term <= vote_request.argmax([], :term) {|v| [v.term]}
    voted_for_in_current_term <= (voted_for * st.current_term).pairs(:term => :term) do |v, t|
      [v.candidate]
    end
    # can only be potential candidate if the candidate's log is at least as complete as our local log
    potential_candidates <= (vote_request * logger.status).pairs do |v, l|
      condition_1 = (v.last_log_term > l.last_term)
      condition_2 = (v.last_log_term == l.last_term and v.last_log_index >= l.last_index)
      v if condition_1 or condition_2
    end
    voted_for_in_current_step <= potential_candidates.argagg(:choose, [], :from) {|v| [v.from]}
    # grant the vote if we haven't voted for anyone else OR if this is the server we already voted for
    vote_response <~ (vote_request * voted_for_in_current_step * st.current_term).combos do |r, v, t|
      grant_vote = (r.from == v.candidate and not voted_for_in_current_term.exists?) or voted_for_in_current_term.include?([r.from])
      [r.from, ip_port, t.term, grant_vote]
    end
    # reset the timer if we grant a vote to a candidate
    st.reset_timer <= (vote_request * voted_for_in_current_step * st.current_term).combos do |r, v, t|
      grant_vote = (r.from == v.candidate and not voted_for_in_current_term.exists?) or voted_for_in_current_term.include?([r.from])
      [random_timeout] if grant_vote
    end
    # update if we hadn't voted for anyone before
    voted_for <+ (voted_for_in_current_step * st.current_term).pairs do |v, t|
      [t.term, v.candidate] if not voted_for_in_current_term.exists?
    end
  end

  bloom :send_heartbeats do
    append_entries_request <~ (heartbeat * members * st.current_state * st.current_term * logger.status).combos do |h, m, s, t, l|
      [m.host, ip_port, t.term, l.last_index, l.last_term, nil, l.last_committed] if s.state == 'leader'
    end
  end

  bloom :normal_operation do
    # revert to follower if we get an append_entries_request
    st.set_state <= (st.current_state * append_entries_request * st.current_term).combos do |s, v, t|
      ['follower'] if (s.state == 'candidate' and v.term >= t.term) or (s.state == 'leader' and v.term > t.term)
    end
    # update term if our term is stale
    st.set_term <= append_entries_request.argmax([], :term) {|a| [a.term]}
    # reset our timer if the term is current or our term is stale
    st.reset_timer <= (append_entries_request * st.current_term).pairs do |a, t|
      [random_timeout] if a.term >= t.term
    end
    # respond with failure if the previous entry doesn't exist in our log
    append_entries_response <~ (append_entries_request * logger.status * st.current_term).combos do |a, i, t|
      [a.from, ip_port, t.term, a.prev_log_index + 1, false] if a.prev_log_index > i.last_index
    end
    # success only if log term matches
    append_entries_response <~ (append_entries_request * logger.logs * st.current_state).combos do |a, l, s|
      [a.from, ip_port, a.term, a.prev_log_index + 1, l.term == a.prev_log_term] if a.entry != nil and s.state != 'leader' and l.index == a.prev_log_index
    end
    # update logs if terms match, replace/delete all entries after
    logger.add_log <= (append_entries_request * logger.logs * logger.status * st.current_state).combos do |a, l, stat, s|
      [a.term, a.entry, a.prev_log_index + 1] if a.entry != nil and s.state != 'leader' and l.index == a.prev_log_index and l.term == a.prev_log_term
    end
    # update committed logs
    temp :max_committed <= append_entries_request.argmax([], :commit_index)
    logger.commit_logs_before <= max_committed {|m| [m.commit_index]}
  end

  bloom :update_servers do
    # find the preceding log metadata for all members
    preceding_logs <= (logger.logs * next_index * st.current_state).pairs do |l, i, s|
      [i.host, l.index, l.term] if s.state == 'leader' and l.index == i.index - 1
    end
    # append entries for all next indices
    append_entries_request <~ (heartbeat * logger.logs * preceding_logs * logger.status * st.current_term).combos do |h, l, p, s, t|
      [p.host, ip_port, t.term, p.index, p.term, l.entry, s.last_committed] if l.index == p.index + 1
    end
  end
  
  bloom :leader_operation do
    # step down as leader if our term is stale and update our term
    st.set_state <= (st.current_state * append_entries_response * st.current_term).combos do |s, a, t|
      ['follower'] if a.term > t.term
    end
    st.set_term <= append_entries_response.argmax([], :term) {|a| [a.term]}
    # count only positive commit votes, so we can keep resending failures
    commit.vote <= append_entries_response do |a|
      [a.index, a.from, true] if a.is_success
    end
    # update next index depending on success/failure
    next_index <+- (append_entries_response * next_index).pairs(:from => :host) do |a, i|
      a.is_success ? [a.from, i.index + 1] : [a.from, i.index - 1]
    end
  end
  
  bloom :leader_commit_logs do
    # commit the logs for which we received a majority vote
    logger.commit_logs_before <= commit.race_won {|w| [w.race]}
  end
  
  bloom :handle_client_request do
    # add it to the log
    logger.add_log <= (send_command * st.current_state * st.current_term).pairs do |c, s, t|
      [t.term, c.command] if s.state == 'leader'
    end
    # vote for it ourselves
    commit.vote <= logger.added_log_index {|i| [i.index, ip_port, true]}
    # NETWORK: wait for a commit
    #temp :single_command <= send_command.argmax([], :command)
    #respond_to <+- (single_command * logger.added_log_index).pairs do |c, i|
    #  [c.from, i.index]
    #end
  end
  
  bloom :client_responses do
    # send committed logs into the state machine to execute
    machine.execute <= logger.committed_logs
    # NETWORK: respond to committed command if you are the leader
    #reply_command <~ (machine.result * respond_to * st.current_state).combos do |r, a, s|
    #  [a.client, r.result] if s.state == 'leader' and a.index == r.index
    #end
    # NETWORK: respond with leader if you are not the leader
    #reply_command <~ (send_command * st.current_leader * st.current_state).pairs do |c, l, s|
    #  [c.from, nil, l.leader] if s.state != 'leader'
    #end
    # respond to committed command if you are the leader
    reply_command <= (machine.result * st.current_state).combos do |r, s|
      [r.result] if s.state == 'leader'
    end
    # respond with leader if you are not the leader
    reply_command <= (send_command * st.current_leader * st.current_state).pairs do |c, l, s|
      [nil, l.leader] if s.state != 'leader'
    end
  end
end
