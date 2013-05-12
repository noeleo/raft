Raft Consensus Protocol in Bud
==============================
### Noel Moldvai, Rohit Turumella, James Butkovic, Josh Muhlfelder

Server State
------------
The state of the server is managed by the ServerState Module.

Snooze Timer
------------
The election timer is handled by the SnoozeTimer Module.

Raft
----
Raft is good.

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
