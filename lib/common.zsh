# Shared by bin/undead, lib/hook and lib/undead.zsh.
# UNDEAD_STATE_DIR / UNDEAD_CONFIG_DIR only exist for tests: Codex runs hooks with a scrubbed environment,
# so real installs must use the defaults.

typeset -g UNDEAD_VERSION=0.1.0
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

# Id of the terminal tab or split pane this shell runs in, stable across the terminal's window restoration.
# TERM_PROGRAM guards against ids inherited by other apps started from a tab (e.g. VS Code's terminal).
undead_terminal_id() {
  emulate -L zsh
  REPLY=
  [[ -z $TMUX ]] || return 1
  case $TERM_PROGRAM in
    iTerm.app) [[ $ITERM_SESSION_ID == *:?* ]] && REPLY=iterm2-${ITERM_SESSION_ID#*:} ;;
    Apple_Terminal) [[ -n $TERM_SESSION_ID ]] && REPLY=terminal-${TERM_SESSION_ID##*:} ;;
    *) return 1 ;;
  esac
  [[ $REPLY =~ '^[A-Za-z0-9._-]+$' ]]
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

# The command that resumes a record: tool, session id, then replayed flags.
undead_resume_command() {
  emulate -L zsh
  local -a rec=("${(@f)$(<$1)}")
  [[ $rec[2] =~ '^[0-9a-fA-F-]+$' ]] || return 1
  local -a args=("${(@)rec[4,-1]}")
  if (( $#args )); then
    undead_replay_flags $rec[1] "$rec[1] ${(j: :)${(@q-)args}}" || args=()
    args=("${(@)reply}")
  fi
  case $rec[1] in
    claude) reply=(claude --resume $rec[2] "${(@)args}") ;;
    codex) reply=(codex resume $rec[2] -c check_for_update_on_startup=false "${(@)args}") ;;
    *) return 1 ;;
  esac
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
