Raft Consensus Algorithm in Bud
===============================
This is one of the first implementations of Raft in Bud, a Bloom DSL for Ruby. There are a few changes made to the protocol for simplicity in programming using Bud, explained in the sections below. 

Team: Noel Moldvai, Rohit Turumella, James Butkovic, and Josh Muhlfelder. For CS 194: Distributed Systems, in Spring 2013, taught by Joe Hellerstein and Peter Alvaro. Thanks to Diego Ongaro from Stanford for being an advisor on the Raft Protocol.

We believe leader election and log replication are working properly, but recovery has not been tested. We also have not implemented dynamic membership.

Running a Raft Server
---------------------
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

### Communicating with a Server via Client
A server is meant to be communicated with so that commands can be issued and responses obtained from a state machine.

Components
----------
The large ideas behind Raft are implemented in src/raft.rb. The basic flow is below, and differences are pointed out.

### Leader Election
Leader election works essentially as described in the Raft paper. When servers start up, they begin as followers and listen for any RequestVote and AppendEntries RPCs. If they receive none within a certain period of time (the timeout), then they begin an election, restart their timer, increment their term, and transition to the candidate state. Here, they send out RequestVote RPCs to all other servers every 100ms until a response is received.

When a response is received, it is stored if the terms of both the sender and receiver are equal, and once a majority of votes are received (we count our vote for ourself), a new leader is borne. This is announced by sending empty AppendEntries RPCs to everyone else, and normal operation resumes.

In responding to VoteRequests, a server will only grant a vote if the terms are equal, the requester's log is at least as up to date as the voter's, and if the voter hadn't voted for anyone else in the current term. If the terms are not equal, the server with the lower term will step down and update theirs.

### Log Replication
A client makes a request to a Raft leader (or another server, in which case it replies with the address of the leader), and when the log for this request has been committed, the command is executed and returned.

The leader issues requests to all servers to append a log entry, and if this is successful on a majority of servers, it can be marked as committed. Meanwhile, the leader is constantly updating other servers to get them up to date.

Modules
-------
We have decomposed some elements of our implementation into modules that can stand alone and be tested in isolation.

### Server State
The state of the server is managed by the ServerState Module which implements the ServerStateProtocol interface. Server state includes the current state of the Raft server (either follower, candidate, or leader), the monotonically increasing current term, the leader, and an interface for snoozing the timer/having the alarm go off. Setting the term can only have the effect of increasing `current_term` or not affecting it at all.

```ruby
interface :input, :set_state, [:state]
interface :input, :set_term, [:term]
interface :input, :set_leader, [:leader]
interface :input, :reset_timer, [] => [:reset]
interface :output, :alarm, [] => [:time_out]
```

The tables in ServerState should be "reached into" by the outer module to grab the state and term.
```ruby
table :current_state, [] => [:state]
table :current_term, [] => [:term]
table :current_leader, [] => [:leader]
```

### Logger
The logger keeps track of all logs. The inputs are self-explanatory. `add_log` also outputs the index of the log just added via `added_log_index`, and if `replace_index` is not nil, the entry is inserted at the given index and all following entries are removed.

```ruby
interface :input, :get_status , [] => [:ok]
interface :input, :add_log, [] => [:term, :entry, :replace_index]
interface :input, :commit_logs_before, [] => [:index]
interface :input, :remove_logs_after, [] => [:index]
interface :input, :remove_uncommitted_logs, [] => [:ok]
interface :output, :status, [] => [:last_index, :last_term, :last_committed]
interface :output, :added_log_index, [] => [:index]
interface :output, :committed_logs, [:index] => [:entry]
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

### State Machine
The state machine simply takes input, does computation and spits output. This is a simple ordered state machine where commands are executed in order of index, and the function is simply the identity.

```ruby
interface :input, :execute, [:index] => [:command]
interface :output, :result, [] => [:index, :result]
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

All unit and integration tests can be found and inspected in /test.

References
----------
* The Bloom Language (http://www.bloom-lang.net/)
* Bud (https://github.com/bloom-lang/bud/)
* "In Search of an Understandable Consensus Algorithm" (https://ramcloud.stanford.edu/wiki/download/attachments/11370504/raft.pdf)
* Raft User Study (http://raftuserstudy.s3-website-us-west-1.amazonaws.com/study/)
