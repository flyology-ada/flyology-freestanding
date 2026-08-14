-------------------------- MODULE SchedulerPreemption -------------------------
EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS T1, T2, T3, C1, C2, NoTask, MaxPriority, MaxRetry, Policy

Tasks == {T1, T2, T3}
Cores == {C1, C2}
Policies == {"FIFO", "RoundRobin"}
Phases == {"Ready", "Running"}

VARIABLES phase, current, ready, priority, pending, retry, retryCount,
          lockOwner, saved

vars == <<phase, current, ready, priority, pending, retry, retryCount,
          lockOwner, saved>>

QueueSet(q) == {q[i] : i \in 1..Len(q)}
Occurrences(q, task) == Cardinality({i \in 1..Len(q) : q[i] = task})

Remove(q, task) ==
    LET position == CHOOSE i \in 1..Len(q) : q[i] = task
    IN  SubSeq(q, 1, position - 1) \o SubSeq(q, position + 1, Len(q))

Init ==
    /\ Policy \in Policies
    /\ MaxPriority \in Nat \ {0}
    /\ MaxRetry \in Nat \ {0}
    /\ phase = [task \in Tasks |-> IF task = T1 THEN "Running" ELSE "Ready"]
    /\ current = [core \in Cores |-> IF core = C1 THEN T1 ELSE NoTask]
    /\ ready = <<T2, T3>>
    /\ priority = [task \in Tasks |-> IF task = T2 THEN MaxPriority ELSE 1]
    /\ pending = {}
    /\ retry = {}
    /\ retryCount = [core \in Cores |-> 0]
    /\ lockOwner = NoTask
    /\ saved = {}

PostInterrupt(core) ==
    /\ core \in Cores
    /\ core \notin pending
    /\ pending' = pending \cup {core}
    /\ UNCHANGED <<phase, current, ready, priority, retry, retryCount,
                   lockOwner, saved>>

EnterCritical(core) ==
    /\ core \in Cores
    /\ lockOwner = NoTask
    /\ lockOwner' = core
    /\ UNCHANGED <<phase, current, ready, priority, pending, retry,
                   retryCount, saved>>

LeaveCritical(core) ==
    /\ core \in Cores
    /\ lockOwner = core
    /\ lockOwner' = NoTask
    /\ UNCHANGED <<phase, current, ready, priority, pending, retry,
                   retryCount, saved>>

RetryInterrupt(core) ==
    /\ core \in pending
    /\ lockOwner /= NoTask
    /\ lockOwner /= core
    /\ core \notin retry
    /\ retryCount[core] < MaxRetry
    /\ retry' = retry \cup {core}
    /\ retryCount' = [retryCount EXCEPT ![core] = @ + 1]
    /\ UNCHANGED <<phase, current, ready, priority, pending, lockOwner,
                   saved>>

AcquireInterrupt(core) ==
    /\ core \in pending
    /\ lockOwner = NoTask
    /\ lockOwner' = core
    /\ UNCHANGED <<phase, current, ready, priority, pending, retry,
                   retryCount, saved>>

PreemptHigher(core) ==
    LET task == current[core]
    IN  /\ lockOwner = core
        /\ task \in Tasks
        /\ phase[task] = "Running"
        /\ \E candidate \in QueueSet(ready) :
               priority[candidate] > priority[task]
        /\ current' = [current EXCEPT ![core] = NoTask]
        /\ phase' = [phase EXCEPT ![task] = "Ready"]
        /\ ready' = <<task>> \o ready
        /\ saved' = saved \cup {task}
        /\ pending' = pending \ {core}
        /\ retry' = retry \ {core}
        /\ lockOwner' = NoTask
        /\ UNCHANGED <<priority, retryCount>>

PreemptQuantum(core) ==
    LET task == current[core]
    IN  /\ Policy = "RoundRobin"
        /\ lockOwner = core
        /\ task \in Tasks
        /\ phase[task] = "Running"
        /\ \E candidate \in QueueSet(ready) :
               priority[candidate] = priority[task]
        /\ current' = [current EXCEPT ![core] = NoTask]
        /\ phase' = [phase EXCEPT ![task] = "Ready"]
        /\ ready' = Append(ready, task)
        /\ saved' = saved \cup {task}
        /\ pending' = pending \ {core}
        /\ retry' = retry \ {core}
        /\ lockOwner' = NoTask
        /\ UNCHANGED <<priority, retryCount>>

ConsumeInterrupt(core) ==
    /\ lockOwner = core
    /\ core \in pending
    /\ pending' = pending \ {core}
    /\ retry' = retry \ {core}
    /\ lockOwner' = NoTask
    /\ UNCHANGED <<phase, current, ready, priority, retryCount, saved>>

Dispatch(core, task) ==
    LET position == CHOOSE i \in 1..Len(ready) : ready[i] = task
    IN  /\ core \in Cores
        /\ task \in QueueSet(ready)
        /\ current[core] = NoTask
        /\ phase[task] = "Ready"
        /\ \A candidate \in QueueSet(ready) :
               priority[task] >= priority[candidate]
        /\ \A earlier \in 1..(position - 1) :
               priority[ready[earlier]] < priority[task]
        /\ current' = [current EXCEPT ![core] = task]
        /\ phase' = [phase EXCEPT ![task] = "Running"]
        /\ ready' = Remove(ready, task)
        /\ saved' = saved \ {task}
        /\ UNCHANGED <<priority, pending, retry, retryCount, lockOwner>>

Yield(core) ==
    LET task == current[core]
    IN  /\ task \in Tasks
        /\ lockOwner = NoTask
        /\ current' = [current EXCEPT ![core] = NoTask]
        /\ phase' = [phase EXCEPT ![task] = "Ready"]
        /\ ready' = Append(ready, task)
        /\ UNCHANGED <<priority, pending, retry, retryCount, lockOwner,
                       saved>>

ChangeReadyPriority(task, newPriority) ==
    /\ task \in QueueSet(ready)
    /\ newPriority \in 1..MaxPriority
    /\ newPriority /= priority[task]
    /\ priority' = [priority EXCEPT ![task] = newPriority]
    /\ ready' = Append(Remove(ready, task), task)
    /\ UNCHANGED <<phase, current, pending, retry, retryCount, lockOwner,
                   saved>>

Next ==
    \/ \E core \in Cores : PostInterrupt(core)
    \/ \E core \in Cores : EnterCritical(core)
    \/ \E core \in Cores : LeaveCritical(core)
    \/ \E core \in Cores : RetryInterrupt(core)
    \/ \E core \in Cores : AcquireInterrupt(core)
    \/ \E core \in Cores : PreemptHigher(core)
    \/ \E core \in Cores : PreemptQuantum(core)
    \/ \E core \in Cores : ConsumeInterrupt(core)
    \/ \E core \in Cores, task \in Tasks : Dispatch(core, task)
    \/ \E core \in Cores : Yield(core)
    \/ \E task \in Tasks, newPriority \in 1..MaxPriority :
           ChangeReadyPriority(task, newPriority)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ phase \in [Tasks -> Phases]
    /\ current \in [Cores -> Tasks \cup {NoTask}]
    /\ ready \in Seq(Tasks)
    /\ priority \in [Tasks -> 1..MaxPriority]
    /\ pending \subseteq Cores
    /\ retry \subseteq Cores
    /\ retryCount \in [Cores -> 0..MaxRetry]
    /\ lockOwner \in Cores \cup {NoTask}
    /\ saved \subseteq Tasks

UniqueReady == \A task \in Tasks : Occurrences(ready, task) <= 1

ReadyIffQueued ==
    \A task \in Tasks : (phase[task] = "Ready") <=> (task \in QueueSet(ready))

RunningIffCurrent ==
    \A task \in Tasks :
        (phase[task] = "Running") <=>
        (\E core \in Cores : current[core] = task)

UniqueCurrent ==
    \A left, right \in Cores :
        (left /= right /\ current[left] /= NoTask) =>
        current[left] /= current[right]

SavedContinuationIsReady == saved \subseteq QueueSet(ready)
RetryRetainsRequest == retry \subseteq pending

Safety == TypeOK /\ UniqueReady /\ ReadyIffQueued /\ RunningIffCurrent
          /\ UniqueCurrent /\ SavedContinuationIsReady
          /\ RetryRetainsRequest

=============================================================================
