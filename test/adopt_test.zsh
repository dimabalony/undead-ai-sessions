source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

# `undead adopt` protects agents that were already running: it reads Claude Code's own ~/.claude/sessions/<pid>.json
# and asks the terminal which tab owns the agent's tty. Stand-in agents run in real pseudo-terminals, and osascript is
# shadowed so no real terminal is queried.
U=$ROOT/bin/undead
GUID_A=AAAA1111-2222-3333-4444-555566667777
GUID_N=BBBB1111-2222-3333-4444-555566667777
GUID_C=CCCC1111-2222-3333-4444-555566667777
SESSION=beee9ec1-7552-4c87-8a5a-d12180adb2f6
mkdir -p $SANDBOX/bin $SANDBOX/adoptzdot $HOME/.claude/sessions
print -l -- "PS1='%# '" "PATH=$SANDBOX/agents:\$PATH" > $SANDBOX/adoptzdot/.zshrc

# An agent that reports its own pid and tty, then waits. Run as `claude -f <body> <flags>`, so `ps` shows the flags.
body() {
  print -l -- "print -r -- \$\$ \$(ps -o tty= -p \$\$) > $SANDBOX/agent.$1" "sleep 60" > $SANDBOX/body.$1.zsh
}
body a; body b; body c
# A nested agent: claude under claude, the way an agent starts another one
print -r -- "claude -f $SANDBOX/body.b.zsh --model sonnet" > $SANDBOX/body.n.zsh
# Codex as it really runs: the binary under its node launcher, under the tab's shell
print -r -- "codex -f $SANDBOX/body.c.zsh" > $SANDBOX/body.cx.zsh

# osascript: the real one for lib/json-hooks.js, our tty -> tab lines for undead_tty_tabs
stub_osascript() {
  print -l -- '#!/bin/sh' 'case "$1" in -l) exec /usr/bin/osascript "$@" ;; esac' 'cat >/dev/null 2>&1' > $SANDBOX/bin/osascript
  local line
  for line in "$@"; do print -r -- "printf '%s\\n' '$line'" >> $SANDBOX/bin/osascript; done
  chmod +x $SANDBOX/bin/osascript
}
adopt() { out=$(PATH=$SANDBOX/bin:$PATH $U adopt "$@" 2>&1); rc=$? }
clear_state() { local -a f=($STATE/tabs/*(N) $STATE/shells/*(N)); (( $#f )) && zf_rm -f $f; : }

# A shell that never sourced undead.zsh, exactly like a tab that predates the install
# The trailing sleep keeps the pseudo-terminal's input open, so the shell stays alive with the agent under it
pty_bg $SANDBOX/pty.a "print -r -- 'claude -f $SANDBOX/body.a.zsh --model opus --add-dir /a /b'; sleep 40" ZDOTDIR=$SANDBOX/adoptzdot
PTY_A=$!
pty_bg $SANDBOX/pty.n "print -r -- 'claude -f $SANDBOX/body.n.zsh'; sleep 40" ZDOTDIR=$SANDBOX/adoptzdot
PTY_N=$!
pty_bg $SANDBOX/pty.c "print -r -- 'node -f $SANDBOX/body.cx.zsh'; sleep 40" ZDOTDIR=$SANDBOX/adoptzdot
PTY_C=$!
wait_until 20 test -s $SANDBOX/agent.a || print -r -- "  (stand-in agent A never started)"
wait_until 20 test -s $SANDBOX/agent.b || print -r -- "  (stand-in agent B never started)"
wait_until 20 test -s $SANDBOX/agent.c || print -r -- "  (stand-in codex never started)"

read -r PID_A TTY_A < $SANDBOX/agent.a
read -r PID_B TTY_B < $SANDBOX/agent.b
read -r PID_C TTY_C < $SANDBOX/agent.c
PPID_A=$(ps -o ppid= -p $PID_A 2>/dev/null | tr -d ' ')
# Claude Code writes procStart in UTC, while ps prints local time
utc_start() { REPLY=$(TZ=UTC date -r $(date -j -f '%a %b %e %H:%M:%S %Y' "${(j: :)${=$(ps -o lstart= -p $1)}}" +%s) +'%a %b %e %H:%M:%S %Y') }
utc_start $PID_A; LSTART_A=$REPLY

session_json() {  # session_json PID KIND PROCSTART
  print -r -- "{\"pid\":$1,\"sessionId\":\"$SESSION\",\"cwd\":\"$SANDBOX/work\",\"procStart\":\"$3\",\"kind\":\"$2\",\"entrypoint\":\"cli\"}" \
    > $HOME/.claude/sessions/$1.json
}
session_json $PID_A interactive $LSTART_A
utc_start $PID_B; session_json $PID_B interactive "$REPLY"
stub_osascript "/dev/$TTY_A $GUID_A" "/dev/$TTY_B $GUID_N" "/dev/$TTY_C $GUID_C"

print -r -- "setup"
check "a stand-in claude runs in a pseudo-terminal" test -n "$PID_A"
check "its parent is the tab's shell" eval '[[ ${$(ps -o comm= -p $PPID_A):t} == *zsh ]]'
check "the nested claude runs under another claude" eval '[[ ${$(ps -o comm= -p $(ps -o ppid= -p $PID_B | tr -d " ")):t} == claude ]]'
check "the stand-in codex runs under node" eval '[[ ${$(ps -o comm= -p $(ps -o ppid= -p $PID_C | tr -d " ")):t} == node ]]'

print -r -- "dry run"
adopt --dry-run
check "says what it would adopt" eval '[[ $out == *"would adopt claude $SESSION for tab iterm2-$GUID_A"* ]]'
check "keeps the replayed flags" eval '[[ $out == *"--model opus --add-dir /a /b"* ]]'
check "writes no record" missing $STATE/tabs/iterm2-$GUID_A
check "registers no shell" missing $STATE/shells/$PPID_A
check "writes no log" missing $STATE/log
check "exits 0" test $rc -eq 0

print -r -- "adopt"
adopt
check "writes the record for the agent's tab" record_is iterm2-$GUID_A "claude
$SESSION
$SANDBOX/work
--model
opus
--add-dir
/a
/b"
check "registers the tab's shell" has $STATE/shells/$PPID_A iterm2-$GUID_A
check "...with its start time, so a reused pid is detectable" eval 'line $STATE/shells/$PPID_A 2; [[ $REPLY == "$(ps -o lstart= -p $PPID_A)" ]]'
check "says so in the log" logged "adopted $SESSION for tab iterm2-$GUID_A"
check "leaves the nested agent alone" missing $STATE/tabs/iterm2-$GUID_N
check "...and says why" logged "not a tab shell"
check "climbs past node to find codex's shell, instead of calling it nested" eval '[[ $out == *"codex on $TTY_C"* ]]'
check "...and says Codex can't be adopted" eval '[[ $out == *"Codex saves no pid"* ]]'
check "...without inventing a record for it" missing $STATE/tabs/iterm2-$GUID_C
check "exits 0" test $rc -eq 0

print -r -- "what it refuses to guess"
clear_state; zf_rm -f $STATE/log
session_json $PID_A interactive "Mon Jan  1 00:00:00 2020"   # the same pid, an older process
adopt
check "a session file from an older process is skipped" missing $STATE/tabs/iterm2-$GUID_A
check "...and reported, not silently dropped" eval '[[ $out == *"older process"* ]]'

clear_state
session_json $PID_A subagent $LSTART_A
adopt
check "a session that isn't interactive is skipped" missing $STATE/tabs/iterm2-$GUID_A

clear_state
session_json $PID_A interactive $LSTART_A
stub_osascript "/dev/ttys999 $GUID_N"
adopt
check "a tty with no tab is skipped" missing $STATE/tabs/iterm2-$GUID_A
check "...and reported" eval '[[ $out == *"no tab ids"* ]]'

clear_state
zf_rm -f $HOME/.claude/sessions/$PID_A.json
stub_osascript "/dev/$TTY_A $GUID_A"
adopt
check "a claude with no session file is skipped" missing $STATE/tabs/iterm2-$GUID_A
check "...and reported" eval '[[ $out == *"no session file"* ]]'

clear_state
session_json $PID_A interactive $LSTART_A
kill -KILL $PID_A 2>/dev/null
wait_until 5 eval '! kill -0 $PID_A 2>/dev/null'
adopt
check "a dead pid is skipped" missing $STATE/tabs/iterm2-$GUID_A

kill $PTY_A $PTY_N $PTY_C 2>/dev/null
finish
