source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

W=$SANDBOX/work
CLAUDE_ID=11111111-2222-3333-4444-555555555555
CODEX_ID=019e3f51-cebd-77d2-b342-c1f5f1bd1f60
calls() { [[ -f $SANDBOX/calls ]] && REPLY=$(<$SANDBOX/calls) || REPLY= }
called() { calls; [[ $REPLY == *$1* ]] || { print -r -- "    calls: ${REPLY:-none}"; return 1 } }
not_called() { calls; [[ -z $REPLY ]] }
reset_calls() { rm -f $SANDBOX/calls }
out_has() { [[ "$(<$SANDBOX/out)" == *$1* ]] || { print -r -- "    output: $(<$SANDBOX/out | tr -d '\r' | tail -5)"; return 1 } }
out_lacks() { [[ "$(<$SANDBOX/out)" != *$1* ]] }
agent_exit_logged() { logged "agent in tab iterm2-$1 exited" }

print -r -- "Restoring"
print -rl -- claude $CLAUDE_ID $W --model opus > $STATE/tabs/iterm2-R1
pty_shell $SANDBOX/out "sleep 3" $(iterm R1)
check "a restored iTerm2 tab resumes its claude session" called "claude --resume $CLAUDE_ID --model opus | $W"
check "  ...and says so" out_has "resuming claude session $CLAUDE_ID"
check "  ...and forgets it after the agent exits while the tab stays open" missing $STATE/tabs/iterm2-R1
check "  ...and leaves the resume command for the hook to read flags from" logged "resuming tab iterm2-R1: claude --resume $CLAUDE_ID --model opus"

print -rl -- claude $CLAUDE_ID $W --model opus --append-system-prompt 'be brief' > $STATE/tabs/iterm2-R7
pty_bg $SANDBOX/out "sleep 4; print exit" $(iterm R7) FAKE_SLEEP=2
resume_line() { local -a files=($STATE/shells/<->.cmd(N)); (( $#files )) && REPLY=$(<$files[1]) }
wait_until 3 resume_line
undead_replay_flags claude "$REPLY"
check "while a resumed agent runs, its flags can be read back for the next restore" test "${(j:|:)reply}" = "--model|opus|--append-system-prompt|be brief"
wait

reset_calls
print -rl -- codex $CODEX_ID $W --yolo > $STATE/tabs/iterm2-R2
pty_shell $SANDBOX/out "sleep 1" $(iterm R2)
check "codex resumes without the update prompt and with its flags" called "codex resume $CODEX_ID -c check_for_update_on_startup=false --yolo | $W"

reset_calls
print -rl -- claude $CLAUDE_ID $W > $STATE/tabs/terminal-TERM-R3
pty_shell $SANDBOX/out "sleep 1" TERM_PROGRAM=Apple_Terminal TERM_SESSION_ID=TERM-R3
check "a restored Terminal.app tab resumes too" called "claude --resume $CLAUDE_ID | $W"

reset_calls
print -rl -- claude $CLAUDE_ID $SANDBOX/deleted-worktree > $STATE/tabs/iterm2-R4
pty_shell $SANDBOX/out "sleep 1" $(iterm R4)
check "a session whose directory is gone isn't resumed" not_called
check "  ...a warning is shown" out_has "could not resume"
check "  ...and it is forgotten" missing $STATE/tabs/iterm2-R4

print -rl -- claude '$(touch '$SANDBOX'/pwned)' $W > $STATE/tabs/iterm2-R5
pty_shell $SANDBOX/out "sleep 1" $(iterm R5)
check "a tampered record runs nothing" missing $SANDBOX/pwned
check "  ...and nothing is called" not_called

print -rl -- claude $CLAUDE_ID $W > $STATE/tabs/iterm2-R6
tab_shell R6 "sleep 4" &
sleep 1
pty_shell $SANDBOX/out "sleep 1" $(iterm R6)
check "a second shell in the same tab doesn't resume again" not_called
wait

print -r -- "Forgetting"
reset_calls
pty_shell $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F1 claude'; sleep 3" $(iterm F1)
check "an agent the user closed is forgotten a moment later" missing $STATE/tabs/iterm2-F1

# The terminal quits: the agent exits first, then the shell gets a hangup, as iTerm2 does
quit_after_agent() {
  wait_until 3 test -f $SANDBOX/pid.$1 || return 1
  sleep 0.3
  kill -HUP $(<$SANDBOX/pid.$1)
}
pty_bg $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F2 claude'; sleep 5" $(iterm F2)
quit_after_agent iterm2-F2
sleep 1.5
check "an agent that exits while the terminal quits is kept" test -f $STATE/tabs/iterm2-F2
check "  ...because the shell was gone when the delay ran out" logged "kept tab iterm2-F2: the tab closed"

pty_bg $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F3 FAKE_EXIT=129 claude'; sleep 5" $(iterm F3)
quit_after_agent iterm2-F3
sleep 1.5
check "an agent killed by a hangup is kept" test -f $STATE/tabs/iterm2-F3
check "  ...without even starting the forget timer" eval '! logged "agent in tab iterm2-F3 exited"' 

pty_shell $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F4 claude'; sleep 0.3; print true; sleep 0.3" $(iterm F4)
check "running another command forgets it at once" logged "forgot tab iterm2-F4: new command started"

pty_bg $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F5 claude'; sleep 0.3; print 'FAKE_RECORD=22222222-2222-3333-4444-555555555555 FAKE_TAB=iterm2-F5 FAKE_SLEEP=3 claude'; sleep 4; print exit" $(iterm F5)
sleep 2.5
check "a new session started meanwhile survives the old session's forget timer" has $STATE/tabs/iterm2-F5 22222222
wait

print -r -- "Support message"
reset_calls
print -rl -- 2 1 > $STATE/restores
print -rl -- claude $CLAUDE_ID $W > $STATE/tabs/iterm2-D1
pty_shell $SANDBOX/out "sleep 1" $(iterm D1)
check "the 3rd restore shows the support message" out_has "brought your AI sessions back 3 times"
print -rl -- claude $CLAUDE_ID $W > $STATE/tabs/iterm2-D2
pty_shell $SANDBOX/out "sleep 1" $(iterm D2)
check "other tabs of the same relaunch don't count again" test "${${(f)"$(<$STATE/restores)"}[1]}" = 3
check "  ...or show it again" out_lacks "brought your AI sessions back"
print -rl -- 9 1 > $STATE/restores
mkdir -p $UNDEAD_CONFIG_DIR && print donate=off > $UNDEAD_CONFIG_DIR/config
print -rl -- claude $CLAUDE_ID $W > $STATE/tabs/iterm2-D3
pty_shell $SANDBOX/out "sleep 1" $(iterm D3)
check "donate off hides it" out_lacks "brought your AI sessions back"

pty_bg $SANDBOX/out "print 'sleep 20 &'; sleep 0.3; print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F6 claude'; sleep 6" $(iterm F6)
sleep 3
check "a background job of your own doesn't keep a closed session alive" missing $STATE/tabs/iterm2-F6

pty_bg $SANDBOX/out "print 'FAKE_RECORD=$CLAUDE_ID FAKE_TAB=iterm2-F7 FAKE_STOP=1 claude'; sleep 6" $(iterm F7)
sleep 3
check "a suspended agent keeps its session" test -f $STATE/tabs/iterm2-F7

print -r -- "Unusual shell options"
mkdir -p $SANDBOX/zdot-opts
print -l -- "PS1='%# '" "PATH=$SANDBOX/fake:\$PATH" \
  "setopt ksh_arrays sh_word_split noclobber nomatch err_exit" \
  "theme_precmd() { print THEME-HOOK-RAN }" "precmd_functions=(theme_precmd)" \
  "source $ROOT/lib/undead.zsh" > $SANDBOX/zdot-opts/.zshrc
reset_calls
print -rl -- claude $CLAUDE_ID $W --model opus > $STATE/tabs/iterm2-O1
pty_shell $SANDBOX/out "sleep 1" $(iterm O1) ZDOTDIR=$SANDBOX/zdot-opts
check "resumes in a shell with ksh_arrays and friends" called "claude --resume $CLAUDE_ID --model opus | $W"
check "  ...and keeps the shell's own precmd hook" out_has THEME-HOOK-RAN

print -r -- "Not active"
rm -f $STATE/shells/<->(N)
pty_shell $SANDBOX/out "sleep 0.5" $(iterm T1) TMUX=/tmp/tmux-1/default
check "shells inside tmux don't register" test -z "$(print $STATE/shells/<->(N))"
pty_shell $SANDBOX/out "sleep 0.5" TERM_PROGRAM=WarpTerminal
check "unsupported terminals don't register" test -z "$(print $STATE/shells/<->(N))"

finish
