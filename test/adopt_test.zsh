source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

# `undead adopt` protects agents that were already running. It reads the tab from the agent's own inherited
# environment, Claude's session from ~/.claude/sessions/<pid>.json, and Codex's from the rollout it holds open.
# Stand-in agents run in real pseudo-terminals, so `ps -E` and `lsof` see the real thing.
U=$ROOT/bin/undead
A=AAAA1111-2222-3333-4444-555566667777   # iTerm2, adoptable claude
N=BBBB1111-2222-3333-4444-555566667777   # iTerm2, a claude started by another claude
T=CCCC1111-2222-3333-4444-555566667777   # Terminal.app
V=DDDD1111-2222-3333-4444-555566667777   # VS Code's terminal
M=EEEE1111-2222-3333-4444-555566667777   # inside tmux
C1=F1110000-2222-3333-4444-555566667777  # codex: one cli rollout and one subagent
C2=F2220000-2222-3333-4444-555566667777  # codex: two cli rollouts
C3=F3330000-2222-3333-4444-555566667777  # codex: nothing open
SESSION=beee9ec1-7552-4c87-8a5a-d12180adb2f6
CODEX_ID=019f92e4-7f0f-7f31-a12e-b6238fdfa78f
ROLLOUTS=$HOME/.codex/sessions/2026/09/16
mkdir -p $HOME/.claude/sessions $ROLLOUTS $SANDBOX/adoptzdot
print -l -- "PS1='%# '" "PATH=$SANDBOX/agents:\$PATH" > $SANDBOX/adoptzdot/.zshrc

# An agent that reports its own pid and tty, holds any rollouts it is given open, then waits. Started as
# `claude -f <body> <flags>`, so `ps` shows the flags the user typed.
body() {
  local label=$1 f i=3; shift
  { print -r -- "print -r -- \$\$ \$(ps -o tty= -p \$\$) > $SANDBOX/agent.$label"
    for f in "$@"; do print -r -- "exec $i< ${(q)f}"; (( i++ )); done
    print -r -- "sleep 60"
  } > $SANDBOX/body.$label.zsh
}
rollout() {  # rollout UUID SOURCE_JSON -> path
  local f=$ROLLOUTS/rollout-2026-09-16T10-00-00-$1.jsonl
  # JSONL, like the real thing: only the first line is a JSON object
  print -rl -- "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$1\",\"cwd\":\"$SANDBOX/work\",\"source\":$2}}" \
    '{"type":"event_msg","payload":{"type":"user_message","message":"hello"}}' \
    '{"type":"event_msg","payload":{"type":"agent_message","message":"hi"}}' > $f
  print -r -- $f
}
CLI1=$(rollout $CODEX_ID '"cli"')
CLI2=$(rollout 019f92e4-7f0f-7f31-a12e-b6238fdfa79f '"cli"')
SUB=$(rollout 01a0712f-2c43-75e3-9789-e7f3919e9803 '{"subagent":{"other":"guardian"}}')

body a; body t; body v; body m; body n
body c1 $CLI1 $SUB; body c2 $CLI1 $CLI2; body c3
print -r -- "claude -f $SANDBOX/body.n.zsh --model sonnet" > $SANDBOX/nested.zsh
for label in c1 c2 c3; do print -r -- "codex -f $SANDBOX/body.$label.zsh -s workspace-write" > $SANDBOX/launch.$label.zsh; done

# `ps -E` reads a process's inherited environment, which is how adopt finds the tab. It works on the real agents but
# not on stand-ins started inside these pseudo-terminals (they do have the variables; ps just won't show them), so the
# environment read is the one call that is shadowed. Everything else reaches the real ps.
mkdir -p $SANDBOX/bin $SANDBOX/env
print -l -- '#!/bin/sh' \
  'if [ "$1" = -Eww ]; then' \
  "  cmd=\$(/bin/ps -ww -o command= -p \"\$5\" 2>/dev/null) || exit 1" \
  "  if [ -f $SANDBOX/env/\$5 ]; then printf '%s %s\\n' \"\$cmd\" \"\$(cat $SANDBOX/env/\$5)\"" \
  "  else printf '%s\\n' \"\$cmd\"; fi" \
  '  exit 0' \
  'fi' \
  'exec /bin/ps "$@"' > $SANDBOX/bin/ps
chmod +x $SANDBOX/bin/ps
agent_env() { print -r -- "$2" > $SANDBOX/env/$1 }

adopt() { out=$(PATH=$SANDBOX/bin:$PATH $U adopt "$@" 2>&1); rc=$? }
clear_state() { local -a f=($STATE/tabs/*(N) $STATE/shells/*(N)); (( $#f )) && zf_rm -f $f; : }
one_line() { [[ $1 != *$'\n'* ]] }
term() { print -r -- "TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=w0t0p0:$1" }

# The trailing sleep keeps each pseudo-terminal's input open, so the shell stays alive with its agent under it
start() {  # start LABEL COMMAND ENV...
  local label=$1 cmd=$2; shift 2
  pty_bg $SANDBOX/pty.$label "print -r -- '$cmd'; sleep 40" ZDOTDIR=$SANDBOX/adoptzdot "$@"
  PTYS+=($!)
}
typeset -a PTYS=()
start a "claude -f $SANDBOX/body.a.zsh --model opus --add-dir /a /b"
start n "claude -f $SANDBOX/nested.zsh"
start t "claude -f $SANDBOX/body.t.zsh"
start v "claude -f $SANDBOX/body.v.zsh"
start m "claude -f $SANDBOX/body.m.zsh"
start c1 "node -f $SANDBOX/launch.c1.zsh"
start c2 "node -f $SANDBOX/launch.c2.zsh"
start c3 "node -f $SANDBOX/launch.c3.zsh"
for label in a n t v m c1 c2 c3; do
  wait_until 25 test -s $SANDBOX/agent.$label || print -r -- "  (stand-in agent $label never started)"
done

# Claude Code writes procStart in UTC, while ps prints local time
utc_start() { REPLY=$(TZ=UTC date -r $(date -j -f '%a %b %e %H:%M:%S %Y' "${(j: :)${=$(ps -o lstart= -p $1)}}" +%s) +'%a %b %e %H:%M:%S %Y') }
session_json() {  # session_json PID KIND [PROCSTART]
  local start=$3
  [[ -n $start ]] || { utc_start $1; start=$REPLY }
  print -r -- "{\"pid\":$1,\"sessionId\":\"$SESSION\",\"cwd\":\"$SANDBOX/work\",\"procStart\":\"$start\",\"kind\":\"$2\",\"entrypoint\":\"cli\"}" \
    > $HOME/.claude/sessions/$1.json
}
for label in a t v m n; do
  read -r pid tty < $SANDBOX/agent.$label
  eval "PID_${label:u}=$pid"
  session_json $pid interactive
done
agent_env $PID_A "$(iterm $A)"
agent_env $PID_N "$(iterm $N)"
agent_env $PID_T "$(term $T)"
agent_env $PID_V "TERM_PROGRAM=vscode ITERM_SESSION_ID=w0t0p0:$V"
agent_env $PID_M "$(iterm $M) TMUX=/tmp/tmux-501/default,1,0"
read -r PID_C1 tty < $SANDBOX/agent.c1; agent_env $PID_C1 "$(iterm $C1)"
read -r PID_C2 tty < $SANDBOX/agent.c2; agent_env $PID_C2 "$(iterm $C2)"
read -r PID_C3 tty < $SANDBOX/agent.c3; agent_env $PID_C3 "$(iterm $C3)"
PPID_A=$(ps -o ppid= -p $PID_A 2>/dev/null | tr -d ' ')

# One set of rules decides a tab id, whether the shell reads its own environment or adopt reads an agent's
tab_is() {  # tab_is EXPECTED|- NAME=VALUE...
  local want=$1 kv; shift
  undead_env=()
  for kv in "$@"; do undead_env[${kv%%=*}]=${kv#*=}; done
  [[ $want == - ]] && { ! undead_tab_id } || { undead_tab_id && [[ $REPLY == $want ]] }
}

print -r -- "tab ids"
check "an iTerm2 tab or split pane" tab_is iterm2-$A TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:$A
check "a Terminal.app tab" tab_is terminal-$T TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=w0t0p0:$T
check "VS Code's terminal only inherited its id" tab_is - TERM_PROGRAM=vscode ITERM_SESSION_ID=w0t0p0:$V
check "a pane inside tmux is not a tab" tab_is - TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:$A TMUX=/tmp/tmux-501/default,1,0
check "an id that isn't a plain name is rejected" tab_is - TERM_PROGRAM=iTerm.app 'ITERM_SESSION_ID=w0t0p0:../../etc'
check "the shell reaches the same answer from its own environment" \
  eval 'TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:$A undead_terminal_id && [[ $REPLY == iterm2-$A ]]'

print -r -- "setup"
check "a stand-in claude runs in a pseudo-terminal" test -n "$PID_A"
check "its parent is the tab's shell" eval '[[ ${$(ps -o comm= -p $PPID_A):t} == *zsh ]]'
check "the shadowed ps hands adopt the tab's variables" eval 'PATH=$SANDBOX/bin:$PATH undead_env_of $PID_A && [[ $undead_env[ITERM_SESSION_ID] == *:$A ]]'
check "the nested claude runs under another claude" eval '[[ ${$(ps -o comm= -p $(ps -o ppid= -p $PID_N | tr -d " ")):t} == claude ]]'
check "the stand-in codex runs under node" eval '[[ ${$(ps -o comm= -p $(ps -o ppid= -p $PID_C1 | tr -d " ")):t} == node ]]'
check "...and holds its rollout open" eval '[[ "$(lsof -p $PID_C1 -Fn 2>/dev/null)" == *rollout-2026-09-16T10-00-00-$CODEX_ID* ]]'

print -r -- "dry run"
adopt --dry-run
check "says what it would adopt" eval '[[ $out == *"would adopt claude $SESSION for tab iterm2-$A"* ]]'
check "keeps the replayed flags" eval '[[ $out == *"--model opus --add-dir /a /b"* ]]'
check "writes no record" missing $STATE/tabs/iterm2-$A
check "writes no log" missing $STATE/log
check "exits 0" test $rc -eq 0

print -r -- "adopt"
adopt
check "writes the record for an iTerm2 tab" record_is iterm2-$A "claude
$SESSION
$SANDBOX/work
--model
opus
--add-dir
/a
/b"
check "registers the tab's shell" has $STATE/shells/$PPID_A iterm2-$A
check "...with its start time, so a reused pid is detectable" eval 'line $STATE/shells/$PPID_A 2; [[ $REPLY == "$(ps -o lstart= -p $PPID_A)" ]]'
check "says so in the log" logged "adopted $SESSION for tab iterm2-$A"
check "a Terminal.app tab is adopted too" has $STATE/tabs/terminal-$T claude
check "exits 0" test $rc -eq 0

print -r -- "Codex"
check "the tab's conversation is the one cli rollout it holds open" record_is iterm2-$C1 "codex
$CODEX_ID
$SANDBOX/work
-s
workspace-write"
check "...so a subagent's rollout is ignored" eval '[[ "$(<$STATE/tabs/iterm2-$C1)" != *01a0712f* ]]'
check "two open conversations are not guessed between" missing $STATE/tabs/iterm2-$C2
check "...and reported" eval '[[ $out == *"codex on"*"several open sessions"* ]]'
check "no open conversation is reported too" missing $STATE/tabs/iterm2-$C3
check "...as no open session" eval '[[ $out == *"no open session"* ]]'
check "...with the safe command, not --last" eval '[[ $out == *"codex resume"*"not --last"* ]]'

print -r -- "left alone"
check "a claude started by another claude" missing $STATE/tabs/iterm2-$N
check "...and the log says why" logged "not a tab shell"
check "VS Code's terminal, whose tab id it only inherited" missing $STATE/tabs/iterm2-$V
check "...and the log says which terminal" logged "runs in vscode"
check "an agent inside tmux" missing $STATE/tabs/iterm2-$M
check "...and the log says so" logged "inside tmux"

print -r -- "what it refuses to guess"
clear_state; zf_rm -f $STATE/log
session_json $PID_A interactive "Mon Jan  1 00:00:00 2020"   # the same pid, an older process
adopt
check "a session file from an older process is skipped" missing $STATE/tabs/iterm2-$A
check "...and reported, not silently dropped" eval '[[ $out == *"older process"* ]]'

clear_state
session_json $PID_A subagent
adopt
check "a session that isn't interactive is skipped" missing $STATE/tabs/iterm2-$A

clear_state
zf_rm -f $HOME/.claude/sessions/$PID_A.json
adopt
check "a claude with no session file is skipped" missing $STATE/tabs/iterm2-$A
check "...and reported" eval '[[ $out == *"no session file"* ]]'
check "the message stays on one line per session" one_line "${${(M)${(f)out}:#*no session file*}[1]}"

clear_state
session_json $PID_A interactive
kill -KILL $PID_A 2>/dev/null
wait_until 5 eval '! kill -0 $PID_A 2>/dev/null'
adopt
check "a dead pid is skipped" missing $STATE/tabs/iterm2-$A

kill $PTYS 2>/dev/null
finish
