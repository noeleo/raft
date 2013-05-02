require 'rubygems'
require 'bud'

module Raft
  import ProgressTimer => :timer

  state do
    channel :request_vote, [:@dest, :from, :term, :candidate]
    channel :append_entries, [:@dest, :from, :term, :entry]

    # all of the members in the system, host is respective ip_port
    table :members, [:host] => []
    table :server_state, [] => [:status]
    table :current_term, [] => [:term]
    # votes being requested
    table :vote_request, [] => [:host]

    table :all_votes_for_given_term, [:term, :from] => [:candidate]

    scratch :request_vote_term_max, current_term.schema

    table :all_votes_for_me_in_given_term, [:term, :from] 
  end

  bootstrap do
    # add all the members of the system except yourself
    # TODO: create mechanism to add all members programatically
    members <= [['localhost:12345'], ['localhost:12346'], ['localhost:12347']]
    server_state <= [['candidate']]
    current_term <= [[1]]
    # start the timer with random timeout between 100-500 ms
    timer.set_alarm <= [['electionTimeout', 100 + rand(400)]]
    # vote for yourself
    request_vote <= (members * current_term).pairs do |m,t|
      [m.host, ip_port, t.term_number, ip_port]
    end
  end

  bloom :vote_count do
    all_votes_for_me_in_given_term <= (all_votes_for_given_term * current_term).pairs do |rv,ct|
      if rv.candidate == ip_port
        [ct.term, all_votes_for_given_term.from]
      end
    end
    server_state <=  (all_votes_for_me_in_given_term * current_term).pairs(:term => :term) do |rv,ct|
      if rv.count > (members.count/2)
        ['leader']
      end
    end
  end

  bloom :handle_request_vote do
    all_votes_for_given_term <= (request_vote * current_term).pairs do |rv, ct|
      if ct.term <= rv.term
        # our terms match, or our term is stale
        [rv.term, rv.from, rv.candidate]
      end
      # otherwise the receiver term is stale and we do nothing
    end
    # update our term
    request_vote_term_max <= request_vote.argmax([:term], :term) do |rv|
      [rv.term]
    end
    current_term <+- (request_vote_term_max * current_term) do |reqmax, ct|
      reqmax if ct < reqmax.term
    end
  end

  bloom :timeout_occured do
    # something with timer.alarm
  end
end
