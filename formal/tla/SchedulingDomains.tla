--------------------------- MODULE SchedulingDomains -------------------------
EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS Env, T1, T2, T3, C1, C2, C3, C4,
          SystemDomain, SecondaryDomain, NoDomain, NoCore, NoTask,
          MaxRotations

Tasks == {Env, T1, T2, T3}
Workers == Tasks \ {Env}
Cores == {C1, C2, C3, C4}
Domains == {SystemDomain, SecondaryDomain}
Policies == {"FIFO", "RoundRobin"}
Phases == {"Absent", "Ready", "Running"}

VARIABLES domainCreated, coreDomain, taskDomain, homeCore, phase,
          current, ready, rotations

vars == <<domainCreated, coreDomain, taskDomain, homeCore, phase,
          current, ready, rotations>>

QueueSet(q) == {q[i] : i \in 1..Len(q)}
Occurrences(q, task) == Cardinality({i \in 1..Len(q) : q[i] = task})
Policy(domain) == IF domain = SystemDomain THEN "FIFO" ELSE "RoundRobin"

Init ==
    /\ MaxRotations \in Nat \ {0}
    /\ domainCreated = FALSE
    /\ coreDomain = [core \in Cores |-> SystemDomain]
    /\ taskDomain = [task \in Tasks |->
                         IF task = Env THEN SystemDomain ELSE NoDomain]
    /\ homeCore = [task \in Tasks |-> IF task = Env THEN C1 ELSE NoCore]
    /\ phase = [task \in Tasks |-> IF task = Env THEN "Running" ELSE "Absent"]
    /\ current = [core \in Cores |-> IF core = C1 THEN Env ELSE NoTask]
    /\ ready = [core \in Cores |-> <<>>]
    /\ rotations = [core \in Cores |-> 0]

CreateSecondary(selected) ==
    /\ ~domainCreated
    /\ selected \subseteq Cores
    /\ selected /= {}
    /\ Cores \ selected /= {}
    /\ C1 \notin selected
    /\ \A task \in Tasks :
          phase[task] = "Absent" \/ homeCore[task] \notin selected
    /\ domainCreated' = TRUE
    /\ coreDomain' =
         [core \in Cores |->
            IF core \in selected THEN SecondaryDomain ELSE coreDomain[core]]
    /\ UNCHANGED <<taskDomain, homeCore, phase, current, ready, rotations>>

Admit(task, explicit, requestedDomain, requestedCore, chosenCore) ==
    LET selectedDomain ==
          IF explicit THEN requestedDomain ELSE taskDomain[Env]
    IN  /\ task \in Workers
        /\ phase[task] = "Absent"
        /\ explicit \in BOOLEAN
        /\ requestedDomain \in Domains
        /\ requestedCore \in Cores \cup {NoCore}
        /\ chosenCore \in Cores
        /\ selectedDomain = SystemDomain \/ domainCreated
        /\ coreDomain[chosenCore] = selectedDomain
        /\ requestedCore = NoCore \/ requestedCore = chosenCore
        /\ taskDomain' = [taskDomain EXCEPT ![task] = selectedDomain]
        /\ homeCore' = [homeCore EXCEPT ![task] = chosenCore]
        /\ phase' = [phase EXCEPT ![task] = "Ready"]
        /\ ready' = [ready EXCEPT ![chosenCore] = Append(@, task)]
        /\ UNCHANGED <<domainCreated, coreDomain, current, rotations>>

Dispatch(core) ==
    LET task == Head(ready[core])
    IN  /\ core \in Cores
        /\ current[core] = NoTask
        /\ ready[core] /= <<>>
        /\ phase[task] = "Ready"
        /\ homeCore[task] = core
        /\ taskDomain[task] = coreDomain[core]
        /\ current' = [current EXCEPT ![core] = task]
        /\ phase' = [phase EXCEPT ![task] = "Running"]
        /\ ready' = [ready EXCEPT ![core] = Tail(@)]
        /\ UNCHANGED <<domainCreated, coreDomain, taskDomain, homeCore,
                       rotations>>

RoundRobinRotate(core) ==
    LET outgoing == current[core]
        incoming == Head(ready[core])
    IN  /\ core \in Cores
        /\ Policy(coreDomain[core]) = "RoundRobin"
        /\ outgoing \in Tasks
        /\ ready[core] /= <<>>
        /\ rotations[core] < MaxRotations
        /\ phase[outgoing] = "Running"
        /\ phase[incoming] = "Ready"
        /\ taskDomain[outgoing] = coreDomain[core]
        /\ taskDomain[incoming] = coreDomain[core]
        /\ homeCore[outgoing] = core
        /\ homeCore[incoming] = core
        /\ current' = [current EXCEPT ![core] = incoming]
        /\ phase' = [phase EXCEPT
                        ![outgoing] = "Ready",
                        ![incoming] = "Running"]
        /\ ready' = [ready EXCEPT
                        ![core] = Append(Tail(@), outgoing)]
        /\ rotations' = [rotations EXCEPT ![core] = @ + 1]
        /\ UNCHANGED <<domainCreated, coreDomain, taskDomain, homeCore>>

Next ==
    \/ \E selected \in SUBSET Cores : CreateSecondary(selected)
    \/ \E task \in Workers, explicit \in BOOLEAN,
          requestedDomain \in Domains,
          requestedCore \in Cores \cup {NoCore}, chosenCore \in Cores :
          Admit(task, explicit, requestedDomain, requestedCore, chosenCore)
    \/ \E core \in Cores : Dispatch(core)
    \/ \E core \in Cores : RoundRobinRotate(core)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ domainCreated \in BOOLEAN
    /\ coreDomain \in [Cores -> Domains]
    /\ taskDomain \in [Tasks -> Domains \cup {NoDomain}]
    /\ homeCore \in [Tasks -> Cores \cup {NoCore}]
    /\ phase \in [Tasks -> Phases]
    /\ current \in [Cores -> Tasks \cup {NoTask}]
    /\ ready \in [Cores -> Seq(Tasks)]
    /\ rotations \in [Cores -> 0..MaxRotations]

SystemNeverEmpty == \E core \in Cores : coreDomain[core] = SystemDomain

SecondaryCreationIsMonotonic ==
    ~domainCreated => \A core \in Cores : coreDomain[core] = SystemDomain

CorePolicyIsDomainPolicy ==
    \A core \in Cores : Policy(coreDomain[core]) \in Policies

UniqueReady ==
    /\ \A core \in Cores, task \in Tasks : Occurrences(ready[core], task) <= 1
    /\ \A left, right \in Cores :
          left /= right => QueueSet(ready[left]) \cap QueueSet(ready[right]) = {}

ReadyIsolation ==
    \A core \in Cores :
        \A task \in QueueSet(ready[core]) :
            /\ phase[task] = "Ready"
            /\ homeCore[task] = core
            /\ taskDomain[task] = coreDomain[core]

ReadyIffQueued ==
    \A task \in Tasks :
        (phase[task] = "Ready") <=>
          (\E core \in Cores : task \in QueueSet(ready[core]))

RunningIsolation ==
    \A core \in Cores :
        current[core] /= NoTask =>
          /\ phase[current[core]] = "Running"
          /\ homeCore[current[core]] = core
          /\ taskDomain[current[core]] = coreDomain[core]

RunningIffCurrent ==
    \A task \in Tasks :
        (phase[task] = "Running") <=>
          (\E core \in Cores : current[core] = task)

UniqueCurrent ==
    \A left, right \in Cores :
        (left /= right /\ current[left] /= NoTask) =>
          current[left] /= current[right]

AbsentHasNoOwnership ==
    \A task \in Tasks :
        phase[task] = "Absent" =>
          (taskDomain[task] = NoDomain /\ homeCore[task] = NoCore)

FIFODoesNotRotate ==
    \A core \in Cores :
        Policy(coreDomain[core]) = "FIFO" => rotations[core] = 0

Safety == TypeOK /\ SystemNeverEmpty /\ SecondaryCreationIsMonotonic
          /\ CorePolicyIsDomainPolicy /\ UniqueReady /\ ReadyIsolation
          /\ ReadyIffQueued /\ RunningIsolation /\ RunningIffCurrent
          /\ UniqueCurrent /\ AbsentHasNoOwnership /\ FIFODoesNotRotate

=============================================================================
