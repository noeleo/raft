Raft Consensus Algorithm in Bud
=================================================
Noel Moldvai, Rohit Turumella, James Butkovic, Josh Muhlfelder at the University of California, Berkeley. For CS 194: Distributed System, in Spring 2013, taught by Joe Hellerstein and Peter Alvaro. Thanks to Diego Ongaro from Stanford for being an advisor on the Raft Protocol.

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
Test Cases to put in

NOTE: Timeout depends on proc speed. Noel's comp is 100 + rand(100) 2.26GHZ core 2 duo
if your proc is slower increase timeout
if faster decrease timeout

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
