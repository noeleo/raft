require 'rubygems'
require 'bud'
require 'snooze_timer'
require 'membership'
require 'server_state'

module RaftProtocol
end

module Raft
  include RaftProtocol
  include ServerState
  import SnoozeTimer => :timer

  TIMEOUT_MIN = 300
  TIMEOUT_MAX = 800

  def set_cluster(cluster)
    @HOSTS = cluster - [[ip_port]]
  end

  state do
    # see Figure 2 in Raft paper to see definitions of RPCs
    # TODO: do we need from field in responses?
    channel :vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :vote_response, [:@dest, :from, :term, :is_granted]
    channel :append_entries_request, [:@dest, :from, :term, :prev_log_index, :prev_log_term, :request_entry, :commit_index]
    channel :append_entries_response, [:@dest, :from, :term, :is_success]

    # all of the members in the system, host is respective ip_port
    table :members, [:host]
    table :leader, [] => [:host]
    table :current_term, [] => [:term]
    scratch :max_term, [:term]
    scratch :single_max_term, [] => [:term]
    # server we voted for in current term
    table :voted_for, [:term] => [:candidate]
    scratch :voted_for_in_current_term, [] => [:candidate]
    scratch :voted_for_in_current_step, [] => [:candidate]
    # keep record of all votes
    table :votes, [:term, :from] => [:is_granted]
    scratch :votes_granted_in_current_term, [:from]
    scratch :request_vote_term_max, current_term.schema
    # this is to determine whether the timer should be reset
    # reset is either going to be set to true or not at all
    scratch :should_reset_timer, [] => [:reset]
    scratch :single_reset, [] => [:reset]

    periodic :heartbeat, 0.1
  end

  bootstrap do
    # add all the members of the system except yourself
    # TODO: create mechanism to add all members programatically
    members <= @HOSTS
    server_state <= [['follower']]
    current_term <= [[1]]
    # start the timer
    timer.set_alarm <= [[TIMEOUT_MIN + rand(TIMEOUT_MAX-TIMEOUT_MIN)]]
  end

  bloom :timeout do
    # increment current term
    max_term <= (timer.alarm * server_state * current_term).combos do |a, s, t|
      [t.term + 1] if s.state != 'leader'
    end
    # transition to candidate state
    possible_server_states <= (timer.alarm * server_state).pairs do |t, s|
      ['candidate'] if s.state != 'leader'
    end
    stdio <~ server_state do |s|
      #puts "#{ip_port} is now a #{s.state} in term #{current_term.first.term}"
      [s]
    end
    # vote for yourself
    votes <= (timer.alarm * server_state * current_term).combos do |a,s,t|
      [t.term, ip_port, true] if s.state != 'leader'
    end
    # reset the alarm
    should_reset_timer <= (timer.alarm * server_state).pairs do |a|
      [true] if s.state != 'leader'
    end
    # send out request vote RPCs
    vote_request <~ (timer.alarm * members * server_state * current_term).combos do |a, m, s, t|
      # TODO: put actual indicies in here after we implement logs
      [m.host, ip_port, t.term, 0, 0] if s.state != 'leader'
    end
  end

  # send out requests if you are a candidate, with a heartbeat
  bloom :wait_for_vote_responses do
    vote_request <~ (server_state * members * current_term * heartbeat).combos do |s, m, t, h|
      # TODO: put actual indicies in here after we implement logs
      [m.host, ip_port, t.term, 0, 0] if s.state == 'candidate'
    end
  end

  bloom :vote_counting do
    # if we discover our term is stale, step down to follower and update our term
    possible_server_states <= (server_state * vote_response * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    #stdio <~ vote_response.inspected
    max_term <= vote_response.argmax([:term], :term) {|v| [v.term]}
    # record votes if we are in the correct term
    # TODO: is_granted will always be true in votes now because we send out requests all the time if
    # we are a candidate
    votes <= (server_state * vote_response * current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term and v.is_granted
    end
    # store votes granted in the current term
    votes_granted_in_current_term <= (server_state * votes * current_term).combos(votes.term => current_term.term) do |s, v, t|
      [v.from] if s.state == 'candidate' and v.is_granted
    end
    #stdio <~ current_term {|t| [t.term]}
    #stdio <~ [[votes_granted_in_current_term.count]]
    # if we have the majority of votes, then we are leader
    possible_server_states <= (server_state * votes_granted_in_current_term).pairs do |s, v|
      #puts votes_granted_in_current_term.count
      ['leader'] if s.state == 'candidate' and votes_granted_in_current_term.count > (members.count/2)
    end
  end

  bloom :vote_casting do
    #stdio <~ [["begin vote_casting"]]
    # if we discover our term is stale, step down to follower and update our term
    possible_server_states <= (server_state * vote_request * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    max_term <= vote_request.argmax([:term], :term) {|v| [v.term]}
    # TODO: if voted_for in current term is null AND the candidate's log is at least as complete as our local log, then grant our vote, reject others, and reset the election timeout
    voted_for_in_current_term <= (voted_for * current_term).pairs do |v, t|
      [v.candidate] if v.term == t.term
    end
    voted_for_in_current_step <= vote_request.argagg(:choose, [], :from) {|v| [v.from]}
    vote_response <~ (vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
      if r.from == v.candidate and voted_for_in_current_term.count == 0
        [r.from, ip_port, t.term, true]
      else
        [r.from, ip_port, t.term, false]
      end
    end
    should_reset_timer <= (vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
      [true] if r.from == v.candidate and not voted_for_in_current_term.exists?
    end
    voted_for <+ (voted_for_in_current_step * current_term).pairs do |v, t|
      [t.term, v.candidate] if voted_for_in_current_term.count == 0
    end
    #stdio <~ [["end vote_casting"]]
  end

  bloom :send_heartbeats do
    append_entries_request <~ (server_state * members * current_term * heartbeat).combos do |s, m, t, h|
       # TODO: add legit indicies when we do logging
      [m.host, ip_port, t.term, 0, 0, 0, 0] if s.state == 'leader'
    end
  end

  bloom :respond_to_append_entries do
    # revert to follower if we get an append_entries_request
    possible_server_states <= (server_state * append_entries_request * current_term).combos do |s, v, t|
      ['follower'] if (s.state == 'candidate' and v.term >= t.term) or (s.state == 'leader' and v.term > t.term)
    end
    # reset our timer if the term is current or our term is stale
    should_reset_timer <= (append_entries_request * current_term).pairs do |a, t|
      #puts 'hi'
      [true] if a.term >= t.term
    end
    # update term if our term is stale
    #max_term <= append_entries_request.argmax([:term], :term) {|a| [a.term]}
    # TODO: step down as leader if our term is stale
    # TODO: respond to append entries
    # TODO: update leader if we get an append entries (and if we are leader, only if our term is stale)
  end

  # if the timer should be reset, reset it here
  bloom :reset_timer do
    # set timer
    single_reset <= should_reset_timer.argagg(:choose, [], :reset)
    # TODO: set_alarm still gives duplicate key errors... wtf????
    #timer.del_alarm <= single_reset {|s| ['election']}
    #timer.set_alarm <= single_reset {|s| ['election', 100 + rand(400)]}
    timer.set_alarm <= single_reset {|s| [TIMEOUT_MIN + rand(TIMEOUT_MAX-TIMEOUT_MIN)]}
  end

  # take the max of all the possible terms and set that as the current term
  bloom :set_current_term do
    single_max_term <= max_term.argagg(:max, [], :term)
    current_term <+- (single_max_term * current_term).pairs do |m, c|
      [m.term] if m.term > c.term
    end
  end
end
