require 'rubygems'
require 'bud'

module Raft
  import ProgressTimer => :timer

  state do
    # see Figure 2 in Raft paper to see definitions of RPCs
    # TODO: do we need from field in responses?
    channel :request_vote_request, [:@dest, :from, :term, :last_log_index, :last_log_term]
    channel :request_vote_response, [:@dest, :from, :term, :is_granted]
    channel :append_entries_request, [:@dest, :from, :term, :prev_log_index, :prev_log_term, :entries, :commit_index]
    channel :append_entries_response, [:@dest, :from, :term, :is_success]

    # all of the members in the system, host is respective ip_port
    table :members, [:host]
    table :server_state, [] => [:state]
    table :current_term, [] => [:term]
    # keep record of all votes
    table :votes, [:term, :from] => [:is_granted]
    scratch :votes_granted_in_current_term, [:from]

    scratch :request_vote_term_max, current_term.schema
  end

  # TODO: is <= right to update an empty key in a table? does it overwrite or result in error?

  bootstrap do
    # add all the members of the system except yourself
    # TODO: create mechanism to add all members programatically
    members <= [['localhost:12345'], ['localhost:12346'], ['localhost:12347']]
    # TODO: is this going to work to remove yourself? need it to happen now, not later
    members <- [[ip_port]]
    server_state <= [['follower']]
    current_term <= [[1]]
    # start the timer with random timeout between 100-500 ms
    timer.set_alarm <= [['electionTimeout', 100 + rand(400)]]
  end

  bloom :timeout do
    # TODO: change timer so that we can just reset it, not name it every time
    # increment current term
    current_term <= (timer.alarm * current_term) {|a,t| [t.term + 1]}
    # transition to candidate state
    server_state <= timer.alarm {|t| [['candidate']]}
    # vote for yourself
    votes <= (timer.alarm * current_term).pairs {|a,t| [t.term, ip_port, true]}
    # reset timer
    # TODO: do this correctly
    timer.set_alarm <= [['electionTimeout', 100 + rand(400)]]
    # send out request vote RPCs
    request_vote_request <= (timer.alarm * members * current_term).combos do |a,m,t|
      # TODO: put actual indicies in here after we implement logs
      [m.host, ip_port, t.term, 0, 0]
    end
  end

  bloom :vote_counting do
    # step down to follower if our term is stale
    server_state <= (server_state * request_vote_response * current_term).combos do |s, v, t|
      ['follower'] if s.state == 'candidate' and v.term > t.term
    end
    # record votes if we are in the correct term
    votes <= (server_state * request_vote_response * current_term).combos do |s, v, t|
      [v.term, v.from, v.is_granted] if s.state == 'candidate' and v.term == t.term
    end
    # store votes granted in the current term
    votes_granted_in_current_term <= (server_state * votes * current_term).combos(votes.term => current_term.term) do |s, v, t|
      [v.from] if s.state == 'candidate' and v.is_granted
    end
    # if we have the majority of votes, then we are leader
    server_state <=  (server_state * votes_granted_in_current_term) do |s, v|
      ['leader'] if s.state == 'candidate' and votes_granted_in_current_term.count > (members.count/2)
    end
  end

  bloom :vote_responses do
    all_votes_for_given_term <= (request_vote_response * current_term).pairs do |rv, ct|
      if ct.term <= rv.term
        # our terms match, or our term is stale
        [rv.term, rv.from, rv.from]
      end
      # otherwise the receiver term is stale and we do nothing
    end
    # update our term
    request_vote_term_max <= request_vote.argmax([:term], :term) do |rv|
      [rv.term]
    end
    current_term <= (request_vote_term_max * current_term) do |reqmax, ct|
      reqmax if ct < reqmax.term
    end
  end

  bloom :send_heartbeats do
  end

end
