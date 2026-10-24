source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

# Agents in tmux panes, on a tmux server of the suite's own (tmux -L), never the default socket. Stand-in agents run
# the real hook from the pane's shell, and a stopped server stands in for a reboot.
(( $+commands[tmux] )) || { print -r -- "  skipped: tmux is not installed"; exit 0 }
unset TMUX_TMPDIR TMUX_PANE
L=undead-test-$$
T=(tmux -L $L -f $SANDBOX/tmux.conf)
trap '$T kill-server 2>/dev/null; cleanup' EXIT

W=$SANDBOX/work W2=$SANDBOX/work2 W3=$SANDBOX/work3
mkdir -p $W2 $W3 $SANDBOX/tbin $SANDBOX/zdot-tmux
A=aaaaaaaa-1111-4111-8111-111111111111   # claude, main:0, the session's first pane
B=bbbbbbbb-1111-4111-8111-111111111111   # claude, split pane in main:1 "work"
C=019e3f51-cccc-77d2-b342-c1f5f1bd1f60   # codex, main:1 "work"
D=dddddddd-1111-4111-8111-111111111111   # claude, session "side"
E=eeeeeeee-1111-4111-8111-111111111111   # claude, main:2, closed by the user
for id in $A $B $D $E; do save_transcript claude $id; done
ROLLOUT=$HOME/.codex/sessions/2026/10/23/rollout-2026-10-23T10-00-00-$C.jsonl
mkdir -p ${ROLLOUT:h}
print -r -- "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$C\",\"cwd\":\"$W\",\"source\":\"cli\"}}" > $ROLLOUT

# A stand-in agent logs how it was called, then becomes a process named claude/codex (a symlink to zsh) that sends
# SessionStart to the real hook, the way the agents do, and runs until it is killed or its sleep ends
cat > $SANDBOX/agent-body.zsh <<EOF
# zsh run as claude or codex emulates csh (the first letter decides), so the body asks for zsh
emulate -R zsh
tool=\$1; shift
sid=\$FAKE_SID
[[ \$1 == (--resume|resume) ]] && sid=\$2
transcript=null
[[ \$tool == codex ]] && transcript='"$ROLLOUT"'
print -r -- "{\"session_id\":\"\$sid\",\"cwd\":\"\$PWD\",\"transcript_path\":\$transcript,\"hook_event_name\":\"SessionStart\"}" > $SANDBOX/json.\$\$
/bin/sh -c "'$ROOT/lib/hook' \$tool start < '$SANDBOX/json.\$\$'; :"
print -r -- \$\$ > $SANDBOX/running.\$sid
sleep \${FAKE_SLEEP:-120}
exit 0
EOF
for name in claude codex; do
  print -l -- '#!/bin/zsh -f' "print -r -- \"$name \$* | \$PWD\" >> $SANDBOX/calls" \
    "exec $SANDBOX/agents/$name -f $SANDBOX/agent-body.zsh $name \"\$@\"" > $SANDBOX/tbin/$name
  chmod +x $SANDBOX/tbin/$name
done
print -l -- "PS1='%# '" "PATH=$SANDBOX/tbin:\$PATH" "source $ROOT/lib/undead.zsh" > $SANDBOX/zdot-tmux/.zshrc
print -l -- 'set -g default-shell /bin/zsh' 'set -g default-command "exec /bin/zsh --no-globalrcs -i"' \
  'set -g base-index 0' > $SANDBOX/tmux.conf

# The server's environment is the one its panes start with: started from an iTerm2 tab, so the panes inherit a tab id
server() { env ZDOTDIR=$SANDBOX/zdot-tmux TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:OUTER $T "$@" }
server_pid() { $T display-message -p '#{pid}' 2>/dev/null }
type_in() { $T send-keys -t $1 "$2" Enter }
count() { REPLY=$(grep -c -- "$1" $SANDBOX/calls 2>/dev/null); REPLY=${REPLY:-0} }
called_once() { count "$1"; (( REPLY == 1 )) || { print -r -- "    called $REPLY times: $1"; return 1 } }
not_called() { count "$1"; (( REPLY == 0 )) }
shells() { local -a f=($STATE/shells/<->(N)); (( $#f == $1 )) }
records() { local -a f=($STATE/tabs/tmux-*(N)); (( $#f == $1 )) }
key_of() { local f; for f in $STATE/tabs/tmux-*(N); do [[ ${${(f)"$(<$f)"}[2]} == $1 ]] && { REPLY=${f:t}; return 0 }; done; return 1 }
side_of() { key_of $1 && REPLY=$(<$STATE/tmux/$REPLY) }
windows() { REPLY=$($T list-windows -t "=$1" -F '#{window_index}:#{window_name}:#{window_panes}' 2>/dev/null | tr '\n' ' ') }

print -r -- "Recording"
server new-session -d -s main -c $W
server new-window -t main:1 -n work -c $W
server split-window -t main:1 -c $W2
server new-session -d -s side -c $W
check "every pane's shell registers" wait_until 10 shells 4
OLD=$(server_pid)
type_in main:0.0 "FAKE_SID=$A claude --model opus"
type_in main:1.0 "FAKE_SID=$C codex --yolo"
type_in main:1.1 "FAKE_SID=$B claude --effort high"
type_in side:0 "FAKE_SID=$D claude"
check "each agent is recorded under its pane" wait_until 15 records 4
key_of $A
check "  ...named after the server and the pane" eval '[[ $REPLY == tmux-<->-$OLD-<-> ]]'
check "  ...with its flags" record_is $REPLY "claude
$A
$W
--model
opus"
side_of $A
check "  ...and where the pane is: session main, window 0" eval '[[ ${${(f)REPLY}[4]} == main && ${${(f)REPLY}[5]} == 0 ]]'
side_of $C
check "a window the user named keeps its name" eval '[[ ${${(f)REPLY}[6]} == work && ${${(f)REPLY}[7]} == 0 ]]'
check "codex is recorded with its flags" has $STATE/tabs/$(key_of $C; print $REPLY) --yolo
check "the iTerm2 tab tmux was started from records nothing" missing $STATE/tabs/iterm2-OUTER

print -r -- "Closing a pane"
server new-window -t main:2 -c $W3
wait_until 10 shells 5
type_in main:2 "FAKE_SID=$E claude"
wait_until 15 records 5
key_of $E; E_KEY=$REPLY
server kill-window -t main:2
check "a pane the user closes while tmux runs keeps its record" wait_until 5 eval '[[ "$(<$STATE/tmux/$E_KEY)" == *closed ]]'
check "  ...marked closed" logged "kept tab $E_KEY: its tmux pane was closed while tmux kept running"
check "  ...and nothing reopens it while tmux runs" not_called "--resume $E"

print -r -- "Doctor"
server new-window -t side:1 -c $W
wait_until 10 shells 5
type_in side:1 "$ROOT/bin/undead doctor > $SANDBOX/doctor.out 2>&1; touch $SANDBOX/doctor.done"
wait_until 20 test -f $SANDBOX/doctor.done
check "doctor names the pane" has $SANDBOX/doctor.out "tmux pane side:1.0"
check "  ...knows the shell is registered" has $SANDBOX/doctor.out "This tab's shell is registered"
check "  ...and says how it comes back" has $SANDBOX/doctor.out "the first shell of each session reopens"
server kill-window -t side:1

print -r -- "tmux stops"
rm -f $SANDBOX/calls
kill -TERM $OLD   # what logging out or rebooting does to the server
check "the server stops" wait_until 10 eval '! kill -0 $OLD 2>/dev/null'
sleep 1.5
check "every record is kept" records 5
check "  ...nothing is forgotten" eval '! logged "forgot tab tmux-"'

print -r -- "tmux starts again"
server new-session -d -s main -c $HOME
NEW=$(server_pid)
check "the session's panes come back" wait_until 15 eval 'count "--resume"; (( REPLY >= 2 ))'
wait_until 15 eval 'count "codex resume"; (( REPLY >= 1 ))'
sleep 1
check "  ...the first pane's claude in place, with its flags and folder" called_once "claude --resume $A --model opus | $W"
check "  ...the split pane's claude in its own folder" called_once "claude --resume $B --effort high | $W2"
check "  ...codex with its flags" called_once "codex resume $C -c check_for_update_on_startup=false --yolo | $W"
windows main
check "  ...in their windows: the first in window 0, the split pair in window 1 named work" \
  eval '[[ $REPLY == 0:*:1\ 1:work:2\  ]] || { print -r -- "    windows: $REPLY"; false }'
key_of $A
check "  ...their records now belong to the new panes" eval '[[ $REPLY == tmux-<->-$NEW-<-> ]]'
check "  ...and are logged" logged "restoring $A of main:0 in this pane"
check "a pane the user closed stays closed" not_called "--resume $E"
check "another session's pane waits for its session" not_called "--resume $D"

server new-window -t main -c $W
sleep 2
check "a later shell in the session restores nothing twice" eval 'count "--resume"; (( REPLY == 2 ))'
server new-session -d -s side -c $HOME
check "the other session gets its pane when it starts" wait_until 15 called_once "claude --resume $D | $W"
sleep 1
check "  ...once" called_once "claude --resume $D"

print -r -- "Reopen"
out=$($ROOT/bin/undead reopen $E 2>&1)
check "undead reopen puts a closed pane back into its tmux session" wait_until 15 called_once "claude --resume $E | $W3"
check "  ...and says so" eval '[[ $out == *"Reopened claude session $E in tmux session main"* ]]'
key_of $E
check "  ...as a pane of the running server" eval '[[ $REPLY == tmux-<->-$NEW-<-> ]]'

print -r -- "Quitting the agent"
key_of $A; A_KEY=$REPLY
wait_until 10 test -f $SANDBOX/running.$A
pkill -P $(<$SANDBOX/running.$A) sleep
check "an agent the user quits in a pane is forgotten, as in a tab" wait_until 5 missing $STATE/tabs/$A_KEY
check "  ...along with where its pane was once the shell exits" eval 'type_in "=main:0.0" exit; wait_until 5 missing $STATE/tmux/$A_KEY'

finish
