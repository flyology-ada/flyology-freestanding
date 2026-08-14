---------------------------- MODULE WaitArbitration ---------------------------
EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS T1, T2, MaxGeneration, MaxStale

Tasks == {T1, T2}
Phases == {"Running", "Armed", "Blocked", "Ready"}
Outcomes == {"None", "Pending", "Normal", "Timeout", "Abort"}
TerminalOutcomes == {"Normal", "Timeout", "Abort"}

VARIABLES phase, generation, outcome, winnerCount, staleRejected,
          queued, timer, ready

vars == <<phase, generation, outcome, winnerCount, staleRejected,
          queued, timer, ready>>

QueueSet(q) == {q[i] : i \in 1..Len(q)}
Occurrences(q, task) == Cardinality({i \in 1..Len(q) : q[i] = task})

Remove(q, task) ==
    LET position == CHOOSE i \in 1..Len(q) : q[i] = task
    IN  SubSeq(q, 1, position - 1) \o SubSeq(q, position + 1, Len(q))

Init ==
    /\ MaxGeneration \in Nat \ {0}
    /\ phase = [task \in Tasks |-> "Running"]
    /\ generation = [task \in Tasks |-> 0]
    /\ outcome = [task \in Tasks |-> "None"]
    /\ winnerCount = [task \in Tasks |-> 0]
    /\ staleRejected = [task \in Tasks |-> 0]
    /\ queued = {}
    /\ timer = {}
    /\ ready = <<>>

Arm(task) ==
    /\ task \in Tasks
    /\ phase[task] = "Running"
    /\ generation[task] < MaxGeneration
    /\ phase' = [phase EXCEPT ![task] = "Armed"]
    /\ generation' = [generation EXCEPT ![task] = @ + 1]
    /\ outcome' = [outcome EXCEPT ![task] = "Pending"]
    /\ winnerCount' = [winnerCount EXCEPT ![task] = 0]
    /\ staleRejected' = [staleRejected EXCEPT ![task] = 0]
    /\ queued' = queued \cup {task}
    /\ timer' = timer \cup {task}
    /\ UNCHANGED ready

CommitPending(task) ==
    /\ task \in Tasks
    /\ phase[task] = "Armed"
    /\ outcome[task] = "Pending"
    /\ phase' = [phase EXCEPT ![task] = "Blocked"]
    /\ UNCHANGED <<generation, outcome, winnerCount, staleRejected,
                   queued, timer, ready>>

CommitAlreadyWon(task) ==
    /\ task \in Tasks
    /\ phase[task] = "Armed"
    /\ outcome[task] \in TerminalOutcomes
    /\ phase' = [phase EXCEPT ![task] = "Running"]
    /\ outcome' = [outcome EXCEPT ![task] = "None"]
    /\ winnerCount' = [winnerCount EXCEPT ![task] = 0]
    /\ UNCHANGED <<generation, staleRejected, queued, timer, ready>>

Resolve(task, token, winner) ==
    /\ task \in Tasks
    /\ token = generation[task]
    /\ winner \in TerminalOutcomes
    /\ phase[task] \in {"Armed", "Blocked"}
    /\ outcome[task] = "Pending"
    /\ outcome' = [outcome EXCEPT ![task] = winner]
    /\ winnerCount' = [winnerCount EXCEPT ![task] = @ + 1]
    /\ queued' = queued \ {task}
    /\ timer' = timer \ {task}
    /\ IF phase[task] = "Blocked"
          THEN /\ phase' = [phase EXCEPT ![task] = "Ready"]
               /\ ready' = Append(ready, task)
          ELSE /\ UNCHANGED phase
               /\ UNCHANGED ready
    /\ UNCHANGED <<generation, staleRejected>>

RejectStale(task, token) ==
    /\ task \in Tasks
    /\ phase[task] \in {"Armed", "Blocked"}
    /\ token \in 0..MaxGeneration
    /\ token /= generation[task]
    /\ staleRejected[task] < MaxStale
    /\ staleRejected' = [staleRejected EXCEPT ![task] = @ + 1]
    /\ UNCHANGED <<phase, generation, outcome, winnerCount, queued, timer,
                   ready>>

Dispatch(task) ==
    /\ task \in QueueSet(ready)
    /\ phase[task] = "Ready"
    /\ outcome[task] \in TerminalOutcomes
    /\ phase' = [phase EXCEPT ![task] = "Running"]
    /\ outcome' = [outcome EXCEPT ![task] = "None"]
    /\ winnerCount' = [winnerCount EXCEPT ![task] = 0]
    /\ ready' = Remove(ready, task)
    /\ UNCHANGED <<generation, staleRejected, queued, timer>>

Next ==
    \/ \E task \in Tasks : Arm(task)
    \/ \E task \in Tasks : CommitPending(task)
    \/ \E task \in Tasks : CommitAlreadyWon(task)
    \/ \E task \in Tasks, token \in 0..MaxGeneration,
          winner \in TerminalOutcomes : Resolve(task, token, winner)
    \/ \E task \in Tasks, token \in 0..MaxGeneration :
           RejectStale(task, token)
    \/ \E task \in Tasks : Dispatch(task)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ phase \in [Tasks -> Phases]
    /\ generation \in [Tasks -> 0..MaxGeneration]
    /\ outcome \in [Tasks -> Outcomes]
    /\ winnerCount \in [Tasks -> 0..1]
    /\ staleRejected \in [Tasks -> 0..MaxStale]
    /\ queued \subseteq Tasks
    /\ timer \subseteq Tasks
    /\ ready \in Seq(Tasks)

UniqueReady == \A task \in Tasks : Occurrences(ready, task) <= 1

ReadyIffQueuedForDispatch ==
    \A task \in Tasks : (phase[task] = "Ready") <=> (task \in QueueSet(ready))

PendingRegistrationIsComplete ==
    \A task \in Tasks :
        (phase[task] \in {"Armed", "Blocked"} /\ outcome[task] = "Pending")
        => (task \in queued /\ task \in timer)

WinnerRemovedAllRegistrations ==
    \A task \in Tasks :
        outcome[task] \in TerminalOutcomes
        => (task \notin queued /\ task \notin timer)

RunningIsUnregistered ==
    \A task \in Tasks :
        phase[task] = "Running"
        => (outcome[task] = "None" /\ task \notin queued
            /\ task \notin timer /\ task \notin QueueSet(ready))

AtMostOneWinner == \A task \in Tasks : winnerCount[task] <= 1

WinnerCountMatchesOutcome ==
    \A task \in Tasks :
        (winnerCount[task] = 1) <=> (outcome[task] \in TerminalOutcomes)

Safety == TypeOK /\ UniqueReady /\ ReadyIffQueuedForDispatch
          /\ PendingRegistrationIsComplete /\ WinnerRemovedAllRegistrations
          /\ RunningIsUnregistered /\ AtMostOneWinner
          /\ WinnerCountMatchesOutcome

=============================================================================
