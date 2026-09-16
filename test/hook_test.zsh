source ${0:A:h}/helpers.zsh

EMIT=$SANDBOX/emit.zsh
W=$SANDBOX/work
rollout() { print -r -- "{\"type\":\"session_meta\",\"payload\":{\"id\":\"x\",\"source\":$2}}" > $1 }
rollout $SANDBOX/cli.jsonl '"cli"'
rollout $SANDBOX/guardian.jsonl '{"subagent":{"other":"guardian"}}'

print -r -- "Recording"
tab_shell A1 "print -r -- 'claude --model opus \"fix it\"' > \$UNDEAD_STATE_DIR/shells/\$\$.cmd; claude -f $EMIT claude start $(hook_json aaaa-1 $W)"
check "claude started in a tab is recorded with its flags" record_is iterm2-A1 "claude
aaaa-1
$W
--model
opus"

tab_shell A2 "claude -f -c '/bin/zsh -f -c \"claude -f $EMIT claude start $(hook_json bbbb-2 $W); :\"; :'"
check "claude started by another agent is ignored" missing $STATE/tabs/iterm2-A2
check "  ...because its parent shell is not a tab shell" logged "bbbb-2 was not started from a terminal tab shell"

tab_shell A3 "node -f -c 'codex -f $EMIT codex start $(hook_json cccc-3 $W $SANDBOX/cli.jsonl); :'"
check "codex started through its node launcher is recorded" record_is iterm2-A3 "codex
cccc-3
$W"

tab_shell A4 "codex -f $EMIT codex start $(hook_json dddd-4 $W $SANDBOX/guardian.jsonl)"
check "codex internal sessions are ignored" missing $STATE/tabs/iterm2-A4
check "  ...because of their rollout source" logged "dddd-4 source is dictionary"

tab_shell A5 "(sleep 1.5; cp $SANDBOX/cli.jsonl $SANDBOX/late.jsonl) & codex -f $EMIT codex start $(hook_json eeee-5 $W $SANDBOX/late.jsonl)"
check "codex is recorded once its rollout file appears" wait_until 6 test -f $STATE/tabs/iterm2-A5

tab_shell A6 "claude -f $EMIT claude start $(hook_json ffff-6 $W)" TMUX=/tmp/tmux-1/default
check "agents inside tmux are ignored" missing $STATE/tabs/iterm2-A6
check "  ...because tmux shells never register" logged "ffff-6 was not started from a terminal tab shell"

tab_shell A7 "print -rl -- iterm2-A7 'Mon Jan  1 00:00:00 2024' > \$UNDEAD_STATE_DIR/shells/\$\$; claude -f $EMIT claude start $(hook_json aaaa-7 $W)"
check "a stale registration (reused pid) is ignored" missing $STATE/tabs/iterm2-A7
check "  ...because the process start time differs" logged "stale registration for pid"

tab_shell A8 "claude -f $EMIT claude start $(hook_json aaaa-8 $W)" TERM_PROGRAM=vscode
check "other apps that inherited an iTerm2 id are ignored" missing $STATE/tabs/iterm2-A8
check "  ...because their shells never register" logged "aaaa-8 was not started from a terminal tab shell"

env TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=6F0C1D52-TERM UNDEAD_ROOT=$ROOT PATH=$SANDBOX/agents:$PATH \
  zsh -f -i -c "source $ROOT/lib/undead.zsh; cd $W; claude -f $EMIT claude start $(hook_json aaaa-9 $W); :"
check "Terminal.app tabs are recorded" record_is terminal-6F0C1D52-TERM "claude
aaaa-9
$W"

print -r -- "Closing"
print -rl -- claude bbbb-10 $W > $STATE/tabs/iterm2-B1
tab_shell B1 "claude -f $EMIT claude end $(hook_json bbbb-10 $W '' prompt_input_exit)"
check "claude closed by the user is forgotten at once" missing $STATE/tabs/iterm2-B1

print -rl -- claude bbbb-11 $W > $STATE/tabs/iterm2-B2
tab_shell B2 "claude -f $EMIT claude end $(hook_json bbbb-11 $W '' other)"
check "claude killed by a terminal quit is kept" test -f $STATE/tabs/iterm2-B2

print -rl -- claude newer-12 $W > $STATE/tabs/iterm2-B3
tab_shell B3 "claude -f $EMIT claude end $(hook_json older-12 $W '' prompt_input_exit)"
check "closing an older session keeps the newer record" test -f $STATE/tabs/iterm2-B3

print -r -- "Output"
out=$($ROOT/lib/hook claude start < $(hook_json zzzz-13 $W))
check "the hook prints nothing (Claude would add it to the context)" test -z "$out"

finish
