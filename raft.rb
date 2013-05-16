require 'rubygems'
require 'bud'

require 'server_state'
require 'vote_counter'

module RaftProtocol
end

# TODO: coordinate setting the state, NOT in server_state, so that we can be in only one specific state at a tick
module Raft
  include RaftProtocol
  import ServerState => :st
  import VoteCounter => :vc

  # should be initialize but don't want to override Bud initializer
  def set_cluster(cluster)
    @HOSTS = cluster
    @MIN_TIMEOUT = 300
    @MAX_TIMEOUT = 800
  end
  
  def set_timeout(min_time, max_time)
    @MIN_TIMEOUT = min_time
    @MAX_TIMEOUT = max_time
  end
  
  def random_timeout
    @MIN_TIMEOUT + rand(@MAX_TIMEOUT - @MIN_TIMEOUT)
  end
  
  state do
    channel :vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :vote_response, [:@dest, :from, :term, :is_granted]
    channel :append_entries_request, [:@dest, :from, :term, :prev_log_index, :prev_log_term, :request_entry, :commit_index]
    channel :append_entries_response, [:@dest, :from, :term, :is_success]

    table :members, [:host]
    table :voted_for, [:term] => [:candidate]
    scratch :voted_for_in_current_term, [] => [:candidate]
    scratch :voted_for_in_current_step, [] => [:candidate]

    periodic :heartbeat, 0.1
  end

  bootstrap do
    members <= @HOSTS - [[ip_port]]
    st.reset_timer <= [[random_timeout]]
    vc.setup <= [[@HOSTS.count]]
  end
  
  bloom :module_input do
    vc.count_votes <= st.current_term {|t| [t.term]}
  end

  bloom :timeout do
    # increment current term
    st.set_term <= (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      puts "ok #{s.state}"
      [t.term + 1] if s.state != 'leader'
    end
    # transition to candidate state
    st.set_state <= (st.alarm * st.current_state).pairs do |t, s|
      ['candidate'] if s.state != 'leader'
    end
    # reset the timer
    st.reset_timer <= (st.alarm * st.current_state).pairs do |a|
      [random_timeout] if s.state != 'leader'
    end
    # vote for ourselves
    vc.vote <= (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      [t.term, ip_port, true] if s.state != 'leader'
    end
    voted_for <+- (st.alarm * st.current_state * st.current_term).combos do |a, s, t|
      [t.term, ip_port] if s.state != 'leader'
    end
  end

  bloom :send_vote_requests do
    vote_request <~ (heartbeat * members * st.current_state * st.current_term).combos do |h, m, s, t|
      [m.host, ip_port, t.term, 0, 0] if s.state == 'candidate' and not vc.voted.include?([t.term, m.host])
    end
  end

  bloom :count_votes do
    # if we discover our term is stale, step down to follower and update our term
    st.set_state <= (st.current_state * vote_response * st.current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    st.set_term <= vote_response.argmax([:term], :term) {|v| [v.term]}
    # record votes if we are in the correct term
    vc.vote <= (st.current_state * vote_response * st.current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term
    end
    # if we won the election, then we become leader
    st.set_state <= (vc.election_won * st.current_state * st.current_term).combos do |e, s, t|
      #puts "#{ip_port} won with e.term #{e.term} and t.term #{t.term}"
      ['leader'] if s.state == 'candidate' and e.term == t.term
    end
  end

  bloom :cast_votes do
    # if we discover our term is stale, step down to follower and update our term
    st.set_state <= (st.current_state * vote_request * st.current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    st.set_term <= vote_request.argmax([:term], :term) {|v| [v.term]}
    # TODO: if voted_for in current term is null AND the candidate's log is at least as complete as our local log, then grant our vote, reject others, and reset the election timeout
    # TODO: make this so that we will respond with true if we already granted a vote for this server (in case network drops packet)
    voted_for_in_current_term <= (voted_for * st.current_term).pairs(:term => :term) do |v, t|
      [v.candidate]
    end
    voted_for_in_current_step <= vote_request.argagg(:choose, [], :from) {|v| [v.from]}
    vote_response <~ (vote_request * voted_for_in_current_step * st.current_term).combos do |r, v, t|
      [r.from, ip_port, t.term, (r.from == v.candidate and not voted_for_in_current_term.exists?)]
    end
    st.reset_timer <= (vote_request * voted_for_in_current_step * st.current_term).combos do |r, v, t|
      [random_timeout] if r.from == v.candidate and not voted_for_in_current_term.exists?
    end
    voted_for <+ (voted_for_in_current_step * st.current_term).pairs do |v, t|
      [t.term, v.candidate] if not voted_for_in_current_term.exists?
    end
  end

  bloom :send_heartbeats do
    append_entries_request <~ (heartbeat * members * st.current_state * st.current_term).combos do |h, m, s, t|
       # TODO: add legit indicies when we do logging
      [m.host, ip_port, t.term, 0, 0, 0, 0] if s.state == 'leader'
    end
  end

  bloom :normal_operation do
    # revert to follower if we get an append_entries_request
    st.set_state <= (st.current_state * append_entries_request * st.current_term).combos do |s, v, t|
      ['follower'] if (s.state == 'candidate' and v.term >= t.term) or (s.state == 'leader' and v.term > t.term)
    end
    # reset our timer if the term is current or our term is stale
    st.reset_timer <= (append_entries_request * st.current_term).pairs do |a, t|
      [random_timeout] if a.term >= t.term
    end
    # update term if our term is stale
    st.set_term <= append_entries_request.argmax([:term], :term) {|a| [a.term]}
    # TODO: step down as leader if our term is stale
    # TODO: respond to append entries
    # TODO: update leader if we get an append entries (and if we are leader, only if our term is stale)
  end
end
