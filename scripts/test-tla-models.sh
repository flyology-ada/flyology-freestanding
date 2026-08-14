#!/bin/sh
set -eu

java_command=${FLYOLOGY_JAVA:-/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home/bin/java}
tla_jar=${FLYOLOGY_TLA2TOOLS_JAR:-downloads/tla2tools-1.8.0.jar}
java_digest=04005388bac0c272ea914210ca519ce94b2f873ea3962b9874a6859f74d7f279
tla_digest=ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f

check_digest() {
    expected=$1
    file=$2
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    test "$actual" = "$expected"
}

test -x "$java_command" || {
    echo "pinned OpenJDK not found; set FLYOLOGY_JAVA" >&2
    exit 69
}
test -f "$tla_jar" || {
    echo "TLA+ tools not found; place the pinned jar at $tla_jar or set FLYOLOGY_TLA2TOOLS_JAR" >&2
    exit 69
}
check_digest "$java_digest" "$java_command"
check_digest "$tla_digest" "$tla_jar"
test "$("$java_command" -version 2>&1 | sed -n '1p')" = \
    'openjdk version "21.0.11" 2026-04-21'

run_model() {
    name=$1
    module=$2
    expected_generated=$3
    expected_distinct=$4
    allow_terminal_deadlock=$5
    output="build/tla/$name.out"
    metadata="build/tla/$name"

    mkdir -p build/tla
    rm -rf "$metadata"
    if test "$allow_terminal_deadlock" = yes; then
        "$java_command" -XX:+UseParallelGC -jar "$tla_jar" \
            -cleanup -deadlock -noGenerateSpecTE -workers 1 \
            -metadir "$metadata" \
            -config "formal/tla/$name.cfg" "formal/tla/$module.tla" \
            >"$output" 2>&1
    else
        "$java_command" -XX:+UseParallelGC -jar "$tla_jar" \
            -cleanup -noGenerateSpecTE -workers 1 -metadir "$metadata" \
            -config "formal/tla/$name.cfg" "formal/tla/$module.tla" \
            >"$output" 2>&1
    fi

    grep -F 'Model checking completed. No error has been found.' "$output" >/dev/null
    summary=$(grep -E '^[0-9,]+ states generated, [0-9,]+ distinct states found' "$output")
    generated=$(printf '%s\n' "$summary" | awk '{gsub(",", "", $1); print $1}')
    distinct=$(printf '%s\n' "$summary" | awk '{gsub(",", "", $4); print $4}')
    test "$generated" = "$expected_generated"
    test "$distinct" = "$expected_distinct"
    echo "FLYOLOGY:TLA:$name:PASS:GENERATED $generated:DISTINCT $distinct"
}

run_model SchedulerPreemptionRoundRobin SchedulerPreemption 1202689 165888 no
run_model SchedulerPreemptionFIFO SchedulerPreemption 1171969 165888 no
run_model WaitArbitration WaitArbitration 5839 1513 yes
echo 'FLYOLOGY:TLA:PASS'
