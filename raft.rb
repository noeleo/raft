require 'rubygems'
require 'bud'
require 'progress_timer'
require 'membership'

module RaftProtocol
end

module Raft
  include RaftProtocol
  include StaticMembership
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
    table :server_state, [:state]
    table :current_term, [:term]
    scratch :max_term, [] => [:term]
    # server we voted for in current term
    table :voted_for, [:term] => [:candidate]
    scratch :voted_for_in_current_term, [] => [:candidate]
    scratch :voted_for_in_current_step, [] => [:candidate]
    # keep record of all votes
    table :votes, [:term, :from] => [:is_granted]
    scratch :votes_granted_in_current_term, [:from]
    scratch :request_vote_term_max, current_term.schema
  end

  # TODO: is <= right to update an empty key in a table? does it overwrite or result in error?

  bootstrap do
    # add all the members of the system except yourself
    # TODO: create mechanism to add all members programatically
    members <= [['localhost:54321'], ['localhost:54322'], ['localhost:54323'], ['localhost:54324'], ['localhost:54325']]
    # TODO: is this going to work to remove yourself? need it to happen now, not later
    members <- [[ip_port]]
    server_state <= [['follower']]
    current_term <= [[1]]
    # start the timer with random timeout between 100-500 ms
    timer.set_alarm <= [[100 + rand(400)]]
  end

  bloom :timeout do
    stdio <~ [["timeout"]]
    # TODO: change timer so that we can just reset it, not name it every time
    # increment current term
    current_term <= (timer.alarm * current_term).pairs {|a,t| [t.term + 1]}
    # transition to candidate state
    server_state <= timer.alarm {|t| [['candidate']]}
    # vote for yourself
    votes <= (timer.alarm * current_term).pairs {|a,t| [t.term, ip_port, true]}
    # reset timer TODO: do this correctly, since we only have 1 timer with same name each time, we should just have reset interface with single timer
    timer.set_alarm <= [[100 + rand(400)]]
    # send out request vote RPCs
    request_vote_request <~ (timer.alarm * members * current_term).combos do |a,m,t|
      # TODO: put actual indicies in here after we implement logs
      [m.host, ip_port, t.term, 0, 0]
    end
    stdio <~ [["end timeout"]]
  end

  # TODO: this might need to be done if we have to continually send if we don't get response
  bloom :wait_for_vote_responses do
  end

  # TODO: have to change names of max_term and current_term and integrate because we are doing the same thing for vote_counting and vote_casting but on diff channels, maybe make a block for that?
  bloom :vote_counting do
    stdio <~ [["begin vote_counting"]]
    # if we discover our term is stale, step down to follower and update our term
    # TODO: do we have to reset timer if we revert to follower here?
    server_state <+- (server_state * request_vote_response * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    max_term <= request_vote_response.argmax([:term], :term) {|v| [v.term]}
    current_term <= (max_term * current_term).pairs do |m,c|
      [m.term] if m.term > c.term
    end
    # record votes if we are in the correct term
    votes <= (server_state * request_vote_response * current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term
    end
    # store votes granted in the current term
    votes_granted_in_current_term <+ (server_state * votes * current_term).combos(votes.term => current_term.term) do |s, v, t|
      [v.from] if s.state == 'candidate' and v.is_granted
    end
    # if we have the majority of votes, then we are leader
    server_state <=  (server_state * votes_granted_in_current_term).pairs do |s, v|
      ['leader'] if s.state == 'candidate' and votes_granted_in_current_term.count > (members.count/2)
    end
    stdio <~ [["end vote_counting"]]
  end

  bloom :vote_casting do
    stdio <~ [["begin vote_casting"]]
    # if we discover our term is stale, step down to follower and update our term
    server_state <= (server_state * request_vote_request * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' or s.state == 'leader' and v.term > t.term
    end
    max_term <= request_vote_request.argmax([:term], :term) {|v| [v.term]}
    current_term <= (max_term * current_term).pairs do |m,c|
      [m.term] if m.term > c.term
    end
    # TODO: if voted_for in current term is null AND the candidate's log is at least as complete as our local log, then grant our vote, reject others, and reset the election timeout
    voted_for_in_current_term <= (voted_for * current_term).pairs(:term => :term) {|v, t| [v.candidate]}
    voted_for_in_current_step <= request_vote_request.argagg(:choose, [], :dest)
    request_vote_response <~ (request_vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
      if r.from == v.candidate and voted_for_in_current_term.count == 0
        [r.from, ip_port, t.term, true]
      else
        [r.from, ip_port, t.term, false]
      end
    end
    timer.set_alarm <= (request_vote_request * voted_for_in_current_step * current_term).combos do |r, v, t|
      [100 + rand(400)] if r.from == v.candidate and voted_for_in_current_term.count == 0
    end
    voted_for <+ (voted_for_in_current_step * current_term).pairs do |v, t|
      [t.term, v.candidate] if voted_for_in_current_term.count == 0
    end

    stdio <~ [["end vote_casting"]]
  end

  bloom :send_heartbeats do
  end

end
