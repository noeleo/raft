require 'rubygems'
require 'bud'
require 'snooze_timer'
require 'progress_timer'
require 'membership'
require 'server_state'

module RaftProtocol
end

module Raft
  include RaftProtocol
  include StaticMembership
  include ServerState
  #import SnoozeTimer => :timer
  import ProgressTimer => :timer

  state do
    # see Figure 2 in Raft paper to see definitions of RPCs
    # TODO: do we need from field in responses?
    channel :request_vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :request_vote_response, [:@dest, :from, :term, :is_granted]
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

    periodic :heartbeat, 0.01
  end

  bootstrap do
    # add all the members of the system except yourself
    # TODO: create mechanism to add all members programatically
    members <= [['localhost:54321'], ['localhost:54322'], ['localhost:54323'], ['localhost:54324'], ['localhost:54325']]
    # TODO: is this going to work to remove yourself? need it to happen now, not later
    members <- [[ip_port]]
    server_state <= [['follower']]
    current_term <= [[1]]
    # start the timer with random timeout between 100-500 ms
    timer.set_alarm <= [[budtime, 100 + rand(400)]]
  end

  bloom :timeout do
    # increment current term
    current_term <+- (timer.alarm * current_term).pairs {|a,t| [t.term + 1]}
    # transition to candidate state
    server_state <+- timer.alarm {|t| ['candidate']}
    # vote for yourself
    votes <= (timer.alarm * current_term).pairs {|a,t| [t.term, ip_port, true]}
    # reset the alarm
    should_reset_timer <= timer.alarm {|a| [true]}
    # send out request vote RPCs
    request_vote_request <~ (timer.alarm * members * current_term).combos do |a,m,t|
      # TODO: put actual indicies in here after we implement logs
      [m.host, ip_port, t.term, 0, 0]
    end
  end

  # TODO: this might need to be done if we have to continually send if we don't get response
  bloom :wait_for_vote_responses do
  end

  bloom :vote_counting do
    # if we discover our term is stale, step down to follower and update our term
    possible_server_states <= (server_state * request_vote_response * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    max_term <= request_vote_response.argmax([:term], :term) {|v| [v.term]}
    # record votes if we are in the correct term
    votes <= (server_state * request_vote_response * current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term
    end
    # store votes granted in the current term
    votes_granted_in_current_term <= (server_state * votes * current_term).combos(votes.term => current_term.term) do |s, v, t|
      puts 'here'
      [v.from] if s.state == 'candidate' and v.is_granted
    end
    # if we have the majority of votes, then we are leader
    possible_server_states <= (server_state * votes_granted_in_current_term).pairs do |s, v|
      #puts votes_granted_in_current_term.count
      puts 'here'
      ['leader'] if s.state == 'candidate' and votes_granted_in_current_term.count > (members.count/2)
    end
  end

  bloom :vote_casting do
    #stdio <~ [["begin vote_casting"]]
    # if we discover our term is stale, step down to follower and update our term
    possible_server_states <= (server_state * request_vote_request * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    max_term <= request_vote_request.argmax([:term], :term) {|v| [v.term]}
    # TODO: if voted_for in current term is null AND the candidate's log is at least as complete as our local log, then grant our vote, reject others, and reset the election timeout
    voted_for_in_current_term <= (voted_for * current_term).pairs do |v, t|
      [v.candidate] if v.term == t.term
    end
    voted_for_in_current_step <= request_vote_request.argagg(:choose, [], :from) {|v| [v.from]}
    request_vote_response <~ (request_vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
      if r.from == v.candidate and voted_for_in_current_term.count == 0
        [r.from, ip_port, t.term, true]
      else
        [r.from, ip_port, t.term, false]
      end
    end
    should_reset_timer <= (request_vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
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

  # if the timer should be reset, reset it here
  bloom :reset_timer do
    # set timer to be 100-500 ms
    single_reset <= should_reset_timer.argagg(:choose, [], :reset)
    # TODO: set_alarm still gives duplicate key errors... wtf????
    #timer.del_alarm <= single_reset {|s| ['election']}
    #timer.set_alarm <= single_reset {|s| ['election', 100 + rand(400)]}
    timer.set_alarm <= single_reset {|s| [budtime, 100 + rand(400)]}
  end

  # take the max of all the possible terms and set that as the current term
  bloom :set_current_term do
    single_max_term <= max_term.argagg(:max, [], :term)
    current_term <+- (single_max_term * current_term).pairs do |m, c|
      [m.term] if m.term > c.term
    end
  end
end
