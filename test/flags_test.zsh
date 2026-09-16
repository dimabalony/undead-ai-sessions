source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

flags() { undead_replay_flags "$@"; REPLY=${(j:|:)reply} }
flags_are() { flags $1 $2; [[ $REPLY == $3 ]] || { print -r -- "    got: $REPLY"; return 1 } }

print -r -- "Claude flags"
check "plain claude replays nothing" flags_are claude "claude" ""
check "model and permission flags are kept" flags_are claude "claude --model opus --dangerously-skip-permissions" "--model|opus|--dangerously-skip-permissions"
check "--flag=value form is kept" flags_are claude "claude --permission-mode=plan" "--permission-mode=plan"
check "prompt text is dropped" flags_are claude "claude 'fix the login bug' --model sonnet" "--model|sonnet"
check "session flags are dropped" flags_are claude "claude --resume abc -c --session-id x --fork-session --model opus" "--model|opus"
check "-p/--print is dropped" flags_are claude "claude -p hello" ""
check "worktree creation is not replayed" flags_are claude "claude -w feature --effort high" "--effort|high"
check "multi-value flags keep their values" flags_are claude "claude --add-dir /a /b --model opus" "--add-dir|/a|/b|--model|opus"
check "a prompt written after a multi-value flag is dropped" flags_are claude "claude --add-dir ../lib 'fix the login bug'" "--add-dir|../lib"
check "an empty value stays attached to its flag" flags_are claude "claude --model '' --verbose" "--model||--verbose"
check "quoted values are unquoted" flags_are claude "claude --append-system-prompt 'be brief; no emojis'" "--append-system-prompt|be brief; no emojis"
check "a full path to the binary works" flags_are claude "/Users/me/.local/bin/claude --chrome" "--chrome"
check "only the agent's own part of a chain is read" flags_are claude "cd repo && claude --verbose && echo --model" "--verbose"
check "env prefixes are skipped" flags_are claude "FOO=1 command claude --ide" "--ide"
check "a command without claude replays nothing" flags_are claude "ls -la" ""

print -r -- "Codex flags"
check "codex model, sandbox and config are kept" flags_are codex "codex -m gpt-5 -s workspace-write -c model_reasoning_effort=high" "-m|gpt-5|-s|workspace-write|-c|model_reasoning_effort=high"
check "--yolo is kept" flags_are codex "codex --yolo --search" "--yolo|--search"
check "resume subcommand and id are dropped" flags_are codex "codex resume 019e-aa --dangerously-bypass-approvals-and-sandbox" "--dangerously-bypass-approvals-and-sandbox"
check "codex prompt is dropped" flags_are codex "codex 'refactor this' -a on-request" "-a|on-request"

print -r -- "Terminal ids"
term_id() { TERM_PROGRAM=$1 ITERM_SESSION_ID=$2 TERM_SESSION_ID=$3 undead_terminal_id }
check "iTerm2 tab ids work" eval 'term_id iTerm.app w0t0p0:A-GUID "" && [[ $REPLY == iterm2-A-GUID ]]'
check "Terminal.app bare uuid ids work" eval 'term_id Apple_Terminal "" 4D9-AA && [[ $REPLY == terminal-4D9-AA ]]'
check "Terminal.app ids with a wNtNpN: prefix work" eval 'term_id Apple_Terminal "" w0t0p0:4D9-AA && [[ $REPLY == terminal-4D9-AA ]]'
check "an id inherited by another app is refused" eval '! term_id vscode w0t0p0:A-GUID ""'
check "tmux is refused" eval 'TMUX=/tmp/x-1/default term_id iTerm.app w0t0p0:A-GUID ""; (( $? != 0 ))'

print -r -- "Resume command"
save_transcript claude 11111111-2222-3333-4444-555555555555
save_transcript codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60
print -rl -- claude 11111111-2222-3333-4444-555555555555 /tmp --model opus > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "claude resumes with its flags" test "${(j:|:)reply}" = "claude|--resume|11111111-2222-3333-4444-555555555555|--model|opus"
print -rl -- codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60 /tmp > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "codex resumes without the update prompt" test "${(j:|:)reply}" = "codex|resume|019e3f51-cebd-77d2-b342-c1f5f1bd1f60|-c|check_for_update_on_startup=false"
print -rl -- claude 11111111-2222-3333-4444-555555555555 /tmp --evil-flag x --model opus > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "flags in a record are checked again before resuming" test "${(j:|:)reply}" = "claude|--resume|11111111-2222-3333-4444-555555555555|--model|opus"
print -rl -- claude '$(touch /tmp/pwned)' /tmp > $SANDBOX/rec
check "a session id that isn't an id is refused" test "$(undead_resume_command $SANDBOX/rec; print $?)" = 1
print -rl -- claude 33333333-2222-3333-4444-555555555555 /tmp --model opus > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "a claude session with no transcript starts claude fresh with its flags" test "${(j:|:)reply}" = "claude|--model|opus"
check "  ...and says so" test "$undead_resume_fresh" = 1
print -rl -- codex 019e3f51-0000-77d2-b342-c1f5f1bd1f60 /tmp --yolo > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "a codex session with no rollout starts codex fresh" test "${(j:|:)reply}" = "codex|-c|check_for_update_on_startup=false|--yolo"
print -rl -- codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60 /tmp > $SANDBOX/rec
undead_resume_command $SANDBOX/rec
check "a resumable record clears the fresh mark" test -z "$undead_resume_fresh"

print -r -- "Transcripts"
check "a claude transcript is found in any project folder" undead_transcript_exists claude 11111111-2222-3333-4444-555555555555
check "a codex rollout is found in any day folder" undead_transcript_exists codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60
check "a missing one isn't" eval '! undead_transcript_exists claude 33333333-2222-3333-4444-555555555555'
check "CODEX_HOME moves the rollouts" eval '! CODEX_HOME=$SANDBOX/codex-home undead_transcript_exists codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60'
mkdir -p $SANDBOX/codex-home/sessions/2026/01/02
: > $SANDBOX/codex-home/sessions/2026/01/02/rollout-2026-01-02T03-04-05-019e3f51-1111-77d2-b342-c1f5f1bd1f60.jsonl
check "  ...and they are found there" eval 'CODEX_HOME=$SANDBOX/codex-home undead_transcript_exists codex 019e3f51-1111-77d2-b342-c1f5f1bd1f60'
check "CLAUDE_CONFIG_DIR moves the transcripts" \
  eval '! CLAUDE_CONFIG_DIR=$SANDBOX/claude-config undead_transcript_exists claude 11111111-2222-3333-4444-555555555555'
check "a session id that is a pattern matches nothing" eval '! undead_transcript_exists claude "*"'

finish
