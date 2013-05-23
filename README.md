Raft Consensus Algorithm in Bud
===============================
This is one of the first implementations of Raft in Bud, a Bloom DSL for Ruby. There are a few changes made to the protocol for simplicity in programming using Bud, explained in the sections below. 

Team: Noel Moldvai, Rohit Turumella, James Butkovic, and Josh Muhlfelder. For CS 194: Distributed Systems, in Spring 2013, taught by Joe Hellerstein and Peter Alvaro. Thanks to Diego Ongaro from Stanford for being an advisor on the Raft Protocol.

We believe leader election and log replication are working properly, but recovery has not been tested. We also have not implemented dynamic membership.

## Running a Raft Server
Before starting an instance of Raft, you must specify the group of servers that the system will be running on by passing them into the constructor. This is done via an array of addresses, like:  
`['127.0.0.1:54321', '127.0.0.1:54322', '127.0.0.1:54323']`  
Then, to run the code, something like this should be done:
```ruby
cluster = ['127.0.0.1:54321', '127.0.0.1:54322', '127.0.0.1:54323']
r = RaftInstance.new(cluster, :port => 54321)
r.set_timeout(100)
r.run_bg
```
An explicit address instead of localhost should be used, because this is how Bud stores them.

The timeout can also be manually set using `set_timeout(min_timeout, is_random = true)`. A random timeout will be in the range between `min_timeout` milliseconds and twice that, and a non-random timeout will always be the minimum timeout. By default, timeouts are 300ms at minimum and random.

The top-level `raft_server.rb` may be used to run a server, by passing in these arguments on the command line. The first argument is the port on which to run locally and the rest are all members of the cluster.

Components
----------
The large ideas behind Raft are implemented in src/raft.rb. The basic flow is below, and differences are pointed out.

### Leader Election
Leader election works essentially as described in the Raft paper. When servers start up, they begin as followers and listen for any RequestVote and AppendEntries RPCs. If they receive none within a certain period of time (the timeout), then they begin an election, restart their timer, increment their term, and transition to the candidate state. Here, they send out RequestVote RPCs to all other servers every 100ms until a response is received.

When a response is received, it is stored if the terms of both the sender and receiver are equal, and once a majority of votes are received (we count our vote for ourself), a new leader is borne. This is announced by sending empty AppendEntries RPCs to everyone else, and normal operation resumes.

In responding to VoteRequests, a server will only grant a vote if the terms are equal, the requester's log is at least as up to date as the voter's, and if the voter hadn't voted for anyone else in the current term. If the terms are not equal, the server with the lower term will step down and update theirs.

### Log Replication
TODO

Modules
-------
We have decomposed some elements of our implementation into modules that can stand alone and be tested in isolation.

### Server State
The state of the server is managed by the ServerState Module which implements the ServerStateProtocol interface. Server state includes the current state of the Raft server (either follower, candidate, or leader), the monotonically increasing current term, and an interface for snoozing the timer/having the alarm go off. Setting the term can only have the effect of increasing `current_term` or not affecting it at all.

```ruby
interface :input, :set_state, [:state]
interface :input, :set_term, [:term]
interface :input, :reset_timer, [] => [:reset]
interface :output, :alarm, [] => [:time_out]
```

The tables in ServerState should be "reached into" by the outer module to grab the state and term.
```ruby
table :current_state, [] => [:state]
table :current_term, [] => [:term]
```

### Logger
The logger keeps track of all logs. The inputs are self-explanatory. `add_log` also outputs the index of the log just added via `added_log_index`.

```ruby
interface :input, :get_status , [] => [:ok]
interface :input, :add_log, [] => [:term, :entry]
interface :input, :commit_logs_before, [] => [:index]
interface :input, :remove_logs_after, [] => [:index]
interface :input, :remove_uncommitted_logs, [] => [:ok]
interface :output, :status, [] => [:last_index, :last_term, :last_committed]
interface :output, :added_log_index, [] => [:index]
```

The logs table can be reached into to inspect the logs.
```ruby
table :logs, [:index] => [:term, :entry, :is_committed]
```

### Vote Counter
The vote counter counts votes and alerts when an election has been won in the specified race. These are binary ballots in which on a particular "race", voters may vote yay or nay, and the majority wins. Initially, the number of voters must be passed in so that we know when a majority has been reached. When the `count_votes` input is used, the user is alerted when the election has been won by a majority.

```ruby
interface :input, :setup, [] => [:num_voters]
interface :input, :count_votes, [:race]
interface :input, :vote, [:race, :voter] => [:is_granted]
interface :output, :race_won, [:race]
```

The `voted` table can be useful to see who has voted (either granted or not granted).
```ruby
table :voted, [:race, :voter]
```

### Snooze Timer
The election timer is handled by the SnoozeTimer Module. The timer works by setting an alarm with a timeout via the `set_alarm` input interface and having it go off via the `alarm` output. If another `set_alarm` is issued before the current alarm goes off, the alarm will be reset, thereby hitting "snooze" on the alarm. In keeping with the design of keeping everything as simple as possible and only features necessary, the module holds only a single timer at a time.

```ruby
interface :input, :set_alarm, [] => [:time_out]
interface :output, :alarm, [] => [:time_out]
```

Tests
-----
To run the entire test suite, including all unit and integration tests, run from the raft directory:
```bash
ruby -I. test/run_all.rb
```

To run any particular test (snooze_timer, for example), run:
```bash
ruby -I. test/test_snooze_timer.rb
```

NOTE: The effectiveness of election timeouts are dependent on processor speed. Running on a single 2.26 Ghz Core 2 Duo, the timeouts run well at the default 300-600ms.

Below are some of the tests in our suite. Note that this is most likely not complete.

### Timer Tests
The test suite for the SnoozeTimer module is in test_timer.rb. These tests test the following cases:
  1. Testing the Alarm Going Off: A timer is set for 3 seconds. We check to see whether a timer does not go off within a second of setting the timer on. 3.5 seconds after turning on the timer we check to see that it has gone off.
  2. Testing Multiple Timers: We create 2 timers with 3 seconds each. We check to see that both alarms go off after 3 seconds of creation.
  3. Testing Reset of Alarms: We set an alarm for 3 seconds. We wait for 1.5 seconds and make sure the alarm does not go off. We then reset the alarm and make sure it goes off 3.5 seconds of the alarm going off.
  4. Test Multiple Timers at Same Tick: We set a timer for 3 seconds. We wait 4 seconds to make surethe timer goes off.

### Server State Tests
The test suite for the Server State module is in test_server_state.rb. These tests test the following cases:
  1. Test one Server State: We create a cluster and set it's state as a candidate. We then tick it to see that the server state should change.  We then check to see that the state of the server is candidate.
  2. Test Tie Braking: We create a cluster and insert 3 states (candidate, leader, follower). We then tick the time state and check to see that the server is demoted to follower.
  3. Test Duplicate States: We create a cluster and insert 3 states (leader, leader, candidate). After a tick, we check to see that the server is demoted to candidate.
  4. Test Multiple Calls: We create a cluster and first set states as leader, leader. Then after a tick we set the states as follower and candidate. We check to see that one server is the leader and after a tick it becomes a follower. 
  5. Test Term Updates: We create a cluster and set a term as 3 and then as 2. We check to see that the term is 3, the max of the current term (1) and the other term we are trying to set (2).

### Leader Election Tests
The test suite for RAFT Leader Election is in test_raft.rb. The test tests the following case:
  1. Test Single Leader Election: We create a cluster of 5 servers. We then wait for 5 seconds and check to see that a single leader is elected.
  2. Test Leader Failure: If we kill the leader, then another one should be elected.
  3. Test Killing Maximum Number of Servers: Start a cluster of 5 servers, then immediately kill 2 of them. A leader should still be elected.
  4. Test Leader Election Tie: Have 2 nodes vote for each other. Make sure that there is only one leader.
  5. Test Term Increments with Election: Record the term after election #1. Kill the leader so another election starts and check to see if the new term is greater than the old term.

References
----------
* The Bloom Language (http://www.bloom-lang.net/)
* Bud (https://github.com/bloom-lang/bud/)
* "In Search of an Understandable Consensus Algorithm" (https://ramcloud.stanford.edu/wiki/download/attachments/11370504/raft.pdf)
* Raft User Study (http://raftuserstudy.s3-website-us-west-1.amazonaws.com/study/)
