Raft Consensus Algorithm in Bud
=================================================

### Team at UC Berkeley:
* Noel Moldvai
* Rohit Turumella
* James Butkovic
* Josh Muhlfelder

For CS 194: Distributed Systems, in Spring 2013, taught by Joe Hellerstein and Peter Alvaro. Thanks to Diego Ongaro from Stanford for being an advisor on the Raft Protocol.

## Raft
This is one of the first implementations of Raft in Bud, a Bloom DSL for Ruby. There are a few changes made to the protocol for simplicity in programming using Bud.

Before starting an instance of Raft, you must specify the group of servers that the system will be running on. The format for specifying the server addresses is the array version of a Bloom collection, like:  
`[['127.0.0.1:54321'], ['127.0.0.1:54322'], ['127.0.0.1:54323']]`  
Then, to run the code, something like this should be done:
```ruby
cluster = [['127.0.0.1:54321'], ['127.0.0.1:54322'], ['127.0.0.1:54323']]
r = RaftInstance.new(:port => 54321)
r.set_cluster(cluster)
r.run_bg
```
An explicit address instead of localhost should be used, because `set_cluster` removes the address of the current server, which is stored as an explicit address.

Modules
-------
We have decomposed some elements of our implementation into modules that can stand alone and be tested in isolation.

### Server State
The state of the server is managed by the ServerState Module which implements the ServerStateProtocol interface. Server state includes the current state of the Raft server (either follower, candidate, or leader) and the monotonically increasing current term.

ServerStateProtocol Input Interfaces
```ruby
interface :input, :set_state, [:state]
interface :input, :set_term, [:term]
```

ServerState Module Tables
```ruby
table :current_state, [] => [:state]
table :current_term, [] => [:term]
```

### Snooze Timer
The election timer is handled by the SnoozeTimer Module. The timer works by setting an alarm with a timeout via the
`set_alarm` input interface and having it go off via the `alarm` output. If another `set_alarm` is issued before the current alarm goes off, the alarm will be reset, thereby hitting "snooze" on the alarm. In keeping with the design of keeping everything as simple as possible and only features necessary, the module holds only a single timer at a time.

SnoozeTimerProtocol Input Interfaces
```ruby
interface :input, :set_alarm, [] => [:time_out]
interface :output, :alarm, [] => [:time_out]
```
SnoozeTimer Module State
```ruby
table :timer_state, [] => [:start_time, :time_out]
scratch :buffer, timer_state.schema
periodic :timer, 0.1
```

Tests
-----
Unit tests to test the Leader Election Implementation of RAFT in Bud are located in the /test directory.

NOTE: Election timeouts are dependent on processor speed. On a 2.26 Ghz Core 2 Duo, the timeout runs well at 300-800ms.

### Timer Tests
The test suite for the SnoozeTimer module is in test_timer.rb. These tests test the following cases:
  1. Testing the Alarm Going Off: A timer is set for 3 seconds. We check to see whether a timer does not go off within a second of setting the timer on. 3.5 seconds after turning on the timer we check to see that it has gone off.
  2. Testing Multiple Timers: We create 2 timers with 3 seconds each. We check to see that both alarms go off after 3 seconds of creation.
  3. Testing Reset of Alarms: We set an alarm for 3 seconds. We wait for 1.5 seconds and make sure the alarm does not go off. We then reset the alarm and make sure it goes off 3.5 seconds of the alarm going off
  4. Test Multiple Timers at Same Tick: We set a timer for 3 seconds. We wait 4 seconds to make surethe timer goes off.

### Server State Tests
The test suite for the Server State module is in test_server_state.rb. These tests test the following cases:
  1. Test one Server State: We create a cluster and set it's state as a candidate. We then tick it to see that the server state should change.  We then check to see that the state of the server is candidate.
  2. Test Tie Braking: We create a cluster and insert 3 states (candidate, leader, follower). We then tick the time state and check to see that the server is demoted to follower.
  3. Test Duplicate States: We create a cluster and insert 3 states (leader, leader, candidate). After a tick, we check to see that the server is demoted to candidate.
  4. Test Multiple Calls: We create a cluster and first set states as leader, leader. Then after a tick we set the states as follower and candidate. We check to see that one server is the leader and after a tick it becomes a follower. 
  5. Test Term Updates: We create a cluster and set a term as 3 and then as 2. We check to see that the term is 3 instead of 2.

### RAFT Leader Election Tests
The test suite for RAFT Leader Election is in test_raft.rb. The test tests the following case:
  1. Test Single Leader Election: We create a cluster of 5 servers. We then wait for 5 seconds and check to see that a single leader is elected. If we kill the leader, then another one should be elected. 

### Tests that need to be added (will be deleted once done) 

Test: Term Incrementing
-Terms are sent with every RPC
Test A: If RPC Sender Term is stale, receiver should respond with its term
and sender increase their term to the receiver's, and rever to follower state

Test B: If receiver term is stale, receiver reverts to follower and updates term to sender
and processes RPC

Test: Single Leader at a Time

Test: If leader goes down, election should start, a new leader should be elected.
-5 servers, leader goes down, 1 of other 4 should be elected
-Nice to have: election should start when timeout on any other node expires

Test: When leader is elected, it should send AppendEntries to all the other nodes continously. all non leader nodes
should be followers

Test: If ElectionTimeout elapses with no RPCS, new election starts

Test: Split Vote?
-2 servers, each vote for each other
-election is resolved even though there are ties

Test: Term is incremented when new election starts

References
----------
* The Bloom Language (http://www.bloom-lang.net/)
* Bud (https://github.com/bloom-lang/bud/)
* "In Search of an Understandable Consensus Algorithm" (https://ramcloud.stanford.edu/wiki/download/attachments/11370504/raft.pdf)
* Raft User Study (http://raftuserstudy.s3-website-us-west-1.amazonaws.com/study/)
