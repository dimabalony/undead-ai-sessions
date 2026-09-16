# Shared by bin/undead, lib/hook and lib/undead.zsh.
# UNDEAD_STATE_DIR / UNDEAD_CONFIG_DIR only exist for tests: Codex runs hooks with a scrubbed environment,
# so real installs must use the defaults.

typeset -g UNDEAD_VERSION=0.3.3
typeset -g UNDEAD_REPO=https://github.com/dimabalony/undead-ai-sessions
typeset -g UNDEAD_STATE=${UNDEAD_STATE_DIR:-$HOME/.local/state/undead}
typeset -g UNDEAD_CONFIG=${UNDEAD_CONFIG_DIR:-$HOME/.config/undead}

zmodload zsh/datetime
zmodload -F zsh/stat b:zstat
zmodload -F zsh/files b:zf_mkdir b:zf_rm b:zf_mv

undead_log() {
  emulate -L zsh
  local log=$UNDEAD_STATE/log
  [[ -f $log ]] && (( $(zstat +size $log 2>/dev/null) > 200000 )) && zf_mv -f $log $log.old
  print -r -- "$(strftime '%F %T' $EPOCHSECONDS) $*" >> $log
}

# Id of the terminal tab or split pane the environment in undead_env belongs to, stable across the terminal's window
# restoration. TERM_PROGRAM guards against ids inherited by other apps started from a tab (e.g. VS Code's terminal).
# One copy of the rules: the shell fills undead_env from its own environment, `undead adopt` from another process's.
typeset -gA undead_env

undead_tab_id() {
  emulate -L zsh
  REPLY=
  [[ -z $undead_env[TMUX] ]] || return 1
  case $undead_env[TERM_PROGRAM] in
    iTerm.app) [[ $undead_env[ITERM_SESSION_ID] == *:?* ]] && REPLY=iterm2-${undead_env[ITERM_SESSION_ID]#*:} ;;
    Apple_Terminal) [[ -n $undead_env[TERM_SESSION_ID] ]] && REPLY=terminal-${undead_env[TERM_SESSION_ID]##*:} ;;
    *) return 1 ;;
  esac
  [[ $REPLY =~ '^[A-Za-z0-9._-]+$' ]]
}

# This shell's own tab
undead_terminal_id() {
  emulate -L zsh
  undead_env=(TERM_PROGRAM "$TERM_PROGRAM" ITERM_SESSION_ID "$ITERM_SESSION_ID"
              TERM_SESSION_ID "$TERM_SESSION_ID" TMUX "$TMUX")
  undead_tab_id
}

# The tab of a running agent, read from the environment it inherited from its shell. `ps -E` prints a same-user
# process's environment after its command line, so the last assignment of each name wins. The tab's login shell
# itself is off limits (it is started by /usr/bin/login), but the agent under it is not.
undead_env_of() {
  emulate -L zsh
  local w out
  undead_env=()
  out=$(ps -Eww -o command= -p $1 2>/dev/null) || return 1
  for w in ${=out}; do
    case $w in
      (TERM_PROGRAM=*|ITERM_SESSION_ID=*|TERM_SESSION_ID=*|TMUX=*) undead_env[${w%%=*}]=${w#*=} ;;
    esac
  done
  (( ${#undead_env} ))
}

# The `source` of a Codex rollout header: "cli" for a session started in a terminal, otherwise the kind of internal
# session it is. Fails while Codex is still writing the first line.
undead_rollout_source() {
  emulate -L zsh
  local type
  REPLY=
  [[ -n $1 ]] || return 1
  plutil -type type - <<<$1 >/dev/null 2>&1 || return 1
  type=$(plutil -type payload.source - <<<$1 2>/dev/null) || type=missing
  if [[ $type == string ]]; then
    REPLY=$(plutil -extract payload.source raw -o - - <<<$1 2>/dev/null)
  else
    REPLY=$type
  fi
  [[ -n $REPLY ]]
}

undead_config() {
  emulate -L zsh
  local line
  [[ -r $UNDEAD_CONFIG/config ]] || return 1
  for line in "${(@f)$(<$UNDEAD_CONFIG/config)}"; do
    [[ $line == $1=* ]] && { REPLY=${line#*=}; return 0 }
  done
  return 1
}

# Flags worth replaying when a session is resumed, taken from the command line that started the agent.
# Everything else (prompts, --print, --continue, worktree creation, ...) is dropped on purpose.
undead_replay_flags() {
  emulate -L zsh
  local tool=$1 line=$2 w name i start=0
  local -a words bool single multi
  reply=()
  words=("${(@Q)${(z)line}}")
  case $tool in
    claude)
      bool=(--dangerously-skip-permissions --allow-dangerously-skip-permissions --chrome --no-chrome --ide
            --strict-mcp-config --verbose --brief --disable-slash-commands --ax-screen-reader)
      single=(--model --permission-mode --effort --fallback-model --agent --agents --settings --system-prompt
              --append-system-prompt --setting-sources --plugin-dir --teammate-mode --autocompact)
      multi=(--add-dir --mcp-config --allowedTools --allowed-tools --disallowedTools --disallowed-tools --tools --betas) ;;
    codex)
      bool=(--dangerously-bypass-approvals-and-sandbox --yolo --search --no-alt-screen --oss --approve-for-me --strict-config)
      single=(-m --model -p --profile -s --sandbox -a --ask-for-approval -c --config --enable --disable --add-dir
              --local-provider) ;;
    *) return 1 ;;
  esac
  for (( i = 1; i <= $#words; i++ )); do
    [[ ${words[i]:t} == $tool ]] && { start=$((i + 1)); break }
  done
  (( start )) || return 1
  for (( i = start; i <= $#words; i++ )); do
    w=$words[i]
    [[ $w == (\;|\&\&|\|\||\||\&) ]] && break
    [[ $w == *$'\n'* ]] && continue
    name=${w%%=*}
    if (( ${bool[(Ie)$w]} )); then
      reply+=($w)
    elif [[ $w == --*=* ]] && (( ${single[(Ie)$name]} || ${multi[(Ie)$name]} )); then
      reply+=($w)
    elif (( ${single[(Ie)$w]} )) && (( i < $#words )); then
      reply+=($w "$words[i+1]")
      (( i++ ))
    elif (( ${multi[(Ie)$w]} )); then
      reply+=($w)
      while (( i < $#words )) && [[ $words[i+1] != -* && $words[i+1] != (\;|\&\&|\|\||\||\&) && $words[i+1] != *[[:space:]]* ]]; do
        (( i++ ))
        reply+=($words[i])
      done
    fi
  done
  return 0
}

# Whether the agent saved a session, which is what `claude --resume` / `codex resume` need. Claude Code writes
# <config dir>/projects/<cwd, non-alphanumerics as dashes>/<id>.jsonl on the first message, not at start, and nothing
# at all while CLAUDE_CODE_CHILD_SESSION is set; the id is a UUID, so any project folder will do. Codex keeps
# $CODEX_HOME/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl.
undead_transcript_exists() {
  emulate -L zsh
  local -a found
  [[ $2 =~ '^[0-9a-fA-F-]+$' ]] || return 1
  case $1 in
    claude) found=(${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/*/$2.jsonl(N)) ;;
    codex) found=(${CODEX_HOME:-$HOME/.codex}/sessions/*/*/*/rollout-*-$2.jsonl(N)) ;;
    *) return 1 ;;
  esac
  (( $#found ))
}

# The command that resumes a record: tool, session id, then replayed flags. A session the agent never saved can't be
# resumed, so it gets the command that starts the agent fresh with the same flags, and undead_resume_fresh is set.
undead_resume_command() {
  emulate -L zsh
  typeset -g undead_resume_fresh=
  local -a rec=("${(@f)$(<$1)}")
  [[ $rec[2] =~ '^[0-9a-fA-F-]+$' && $rec[1] == (claude|codex) ]] || return 1
  local -a args=("${(@)rec[4,-1]}")
  if (( $#args )); then
    undead_replay_flags $rec[1] "$rec[1] ${(j: :)${(@q-)args}}" || args=()
    args=("${(@)reply}")
  fi
  undead_transcript_exists $rec[1] $rec[2] || undead_resume_fresh=1
  case $rec[1]:$undead_resume_fresh in
    claude:) reply=(claude --resume $rec[2] "${(@)args}") ;;
    claude:1) reply=(claude "${(@)args}") ;;
    codex:) reply=(codex resume $rec[2] -c check_for_update_on_startup=false "${(@)args}") ;;
    codex:1) reply=(codex -c check_for_update_on_startup=false "${(@)args}") ;;
  esac
}

# Whether a process (default: this shell) runs under Claude Code or Codex, looking at most 8 parents up. Claude Code
# shows as claude, or as its .../claude/versions/<version> binary when it started the process itself (agent team
# members); Codex as codex, under a node launcher.
undead_under_agent() {
  emulate -L zsh
  local pid=${1:-$$} ppid comm i
  for i in {0..8}; do
    read -r ppid comm <<<"$(ps -o ppid=,comm= -p $pid 2>/dev/null)"
    [[ ${comm:t} == (claude|codex)* || $comm == */claude/versions/* ]] && return 0
    (( ppid > 1 )) || return 1
    pid=$ppid
  done
  return 1
}

# A live shell registered for the given terminal id, other than the caller.
undead_live_shell_for() {
  emulate -L zsh
  local f pid
  local -a reg
  for f in $UNDEAD_STATE/shells/<->(N); do
    pid=${f:t}
    (( pid == $$ )) && continue
    reg=("${(@f)$(<$f)}")
    [[ $reg[1] == $1 ]] || continue
    kill -0 $pid 2>/dev/null || continue
    [[ $reg[2] == "$(ps -o lstart= -p $pid 2>/dev/null)" ]] && { REPLY=$pid; return 0 }
  done
  return 1
}
