# Test helpers: a throwaway HOME, fake agents and interactive shells in a pseudo-terminal.
# Nothing touches the real ~/.claude, ~/.codex, ~/.zshrc or saved sessions.

ROOT=${${(%):-%x}:A:h:h}
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/undead-test.XXXXXX")
SANDBOX=${SANDBOX:A}

# The suite often runs inside Claude Code, whose session markers would otherwise reach every shell under test
unset TMUX ITERM_SESSION_ID TERM_SESSION_ID TERM_PROGRAM UNDEAD_DISABLE UNDEAD_NO_DONATE ZDOTDIR CODEX_HOME CLAUDECODE \
  CLAUDE_CODE_CHILD_SESSION CLAUDE_CONFIG_DIR
export HOME=$SANDBOX/home
export UNDEAD_STATE_DIR=$HOME/.local/state/undead UNDEAD_CONFIG_DIR=$HOME/.config/undead UNDEAD_FORGET_DELAY=1
STATE=$UNDEAD_STATE_DIR
mkdir -p $HOME $STATE/tabs $STATE/shells $SANDBOX/agents $SANDBOX/fake $SANDBOX/zdot $SANDBOX/work
cleanup() { pkill -f "$SANDBOX" 2>/dev/null; rm -rf $SANDBOX }
trap cleanup EXIT

typeset -gi PASSED=0 FAILED=0
check() {
  local desc=$1; shift
  if "$@"; then
    (( PASSED++ )); print -r -- "  ✓ $desc"
  else
    (( FAILED++ )); print -r -- "  ✗ $desc"
  fi
}
finish() {
  [[ -n $VERBOSE && -f $STATE/log ]] && sed 's/^/    log: /' $STATE/log
  print -r -- "  $PASSED passed, $FAILED failed"
  (( FAILED == 0 ))
  exit
}

has() { [[ -f $1 && "$(<$1)" == *$2* ]] }
missing() { [[ ! -e $1 ]] }
logged() { [[ -f $STATE/log && "$(<$STATE/log)" == *$1* ]] }
line() { [[ -f $1 ]] && REPLY=${${(f)"$(<$1)"}[$2]} }
record_is() { [[ -f $STATE/tabs/$1 && "$(<$STATE/tabs/$1)" == "$2" ]] }
# A saved conversation, so a record resumes instead of starting the agent fresh. Usage: save_transcript claude|codex ID
save_transcript() {
  local dir
  case $1 in
    claude) dir=$HOME/.claude/projects/-work; mkdir -p $dir && : > $dir/$2.jsonl ;;
    codex) dir=$HOME/.codex/sessions/2026/09/16; mkdir -p $dir && : > $dir/rollout-2026-09-16T20-05-16-$2.jsonl ;;
  esac
}
# Runs a command with launchd as its parent, so an agent running the suite (Claude Code's Bash tool) isn't above it.
# Returns at once. Usage: detached COMMAND...
detached() {
  ( zsh -fc 'until (( $(ps -o ppid= -p $$) == 1 )); do sleep 0.05; done; exec "$@"' detached "$@" & )
}
wait_until() {
  local timeout=$1 i; shift
  for (( i = 0; i < timeout * 10; i++ )); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}

# Agents for hook tests: named symlinks to zsh, so `ps` shows them as claude/codex/node like the real ones
for name in claude codex node; do ln -sf /bin/zsh $SANDBOX/agents/$name; done

# run as an agent: sends a hook JSON file to lib/hook through sh -c, the way Claude Code and Codex run hooks
cat > $SANDBOX/emit.zsh <<'EOF'
/bin/sh -c "'$UNDEAD_ROOT/lib/hook' $1 $2 < '$3'; :"
:
EOF

# Writes hook JSON to a file and prints its path. Usage: hook_json SESSION_ID CWD [TRANSCRIPT] [REASON]
hook_json() {
  local transcript=null file=$SANDBOX/json.$1.${4:-other}
  [[ -n $3 ]] && transcript="\"$3\""
  print -r -- "{\"session_id\":\"$1\",\"cwd\":\"$2\",\"transcript_path\":$transcript,\"reason\":\"${4:-other}\",\"hook_event_name\":\"x\"}" > $file
  print -r -- $file
}

# A registered, non-prompting tab shell running commands (for hook tests). Usage: tab_shell GUID COMMANDS [env...]
tab_shell() {
  local guid=$1 cmds=$2; shift 2
  env TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:$guid UNDEAD_ROOT=$ROOT PATH=$SANDBOX/agents:$PATH "$@" \
    zsh -f -i -c "source $ROOT/lib/undead.zsh; cd $SANDBOX/work; $cmds; :"
}

# Fake agents for shell tests: log their arguments and directory, optionally act like the hook, then exit
for name in claude codex; do
  cat > $SANDBOX/fake/$name <<EOF
#!/bin/zsh -f
print -r -- "$name \$* | \$PWD" >> $SANDBOX/calls
[[ -n \$FAKE_TAB ]] && print \$PPID > $SANDBOX/pid.\$FAKE_TAB
[[ -n \$FAKE_RECORD ]] && print -rl -- $name \$FAKE_RECORD \$PWD > \$UNDEAD_STATE_DIR/tabs/\$FAKE_TAB.tmp && mv -f \$UNDEAD_STATE_DIR/tabs/\$FAKE_TAB.tmp \$UNDEAD_STATE_DIR/tabs/\$FAKE_TAB
[[ -n \$FAKE_STOP ]] && kill -TSTP \$\$
sleep \${FAKE_SLEEP:-0}
exit \${FAKE_EXIT:-0}
EOF
  chmod +x $SANDBOX/fake/$name
done
print -l -- "PS1='%# '" "PATH=$SANDBOX/fake:\$PATH" "source $ROOT/lib/undead.zsh" > $SANDBOX/zdot/.zshrc

# An interactive shell in a pseudo-terminal that reads INPUT (a zsh snippet producing keystrokes) and exits at its end.
# Usage: pty_shell OUTFILE INPUT [env...]   (TERM_PROGRAM/ids come from env)
pty_shell() {
  local out=$1 input=$2; shift 2
  # script(1) on macOS doesn't pass end-of-input on, so the shell is told to exit
  { eval "$input"; print exit; sleep 0.5 } | env ZDOTDIR=$SANDBOX/zdot "$@" script -q /dev/null zsh --no-globalrcs -i > $out 2>&1 &
  local pid=$! i
  # A shell that refuses to exit (e.g. it has running jobs) must not hang the suite
  for (( i = 0; i < 300; i++ )); do
    kill -0 $pid 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL $pid 2>/dev/null
  wait $pid 2>/dev/null
}
# Same, but in the background and without exiting at the end (the test ends it, e.g. with a hangup)
pty_bg() {
  local out=$1 input=$2; shift 2
  { eval "$input" } | env ZDOTDIR=$SANDBOX/zdot "$@" script -q /dev/null zsh --no-globalrcs -i > $out 2>&1 &
}
iterm() { print -r -- "TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:$1" }
