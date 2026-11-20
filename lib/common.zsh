# Shared by bin/undead, lib/hook and lib/undead.zsh.
# UNDEAD_STATE_DIR / UNDEAD_CONFIG_DIR only exist for tests: Codex runs hooks with a scrubbed environment,
# so real installs must use the defaults.

typeset -g UNDEAD_VERSION=0.4.0
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
  if [[ -n $undead_env[TMUX] ]]; then
    # tmux (3.2 and later) sets TERM_PROGRAM=tmux in its panes; an app started from a pane inherits TMUX but brings
    # its own TERM_PROGRAM, and an older tmux leaves the outer terminal's, whose tab id belongs to every pane at once
    [[ $undead_env[TERM_PROGRAM] == tmux ]] || return 1
    undead_tmux_pane_id ${undead_env[TMUX]%%,*} "$undead_env[TMUX_PANE]" "$undead_env[TTY]" || return 1
  else
    case $undead_env[TERM_PROGRAM] in
      iTerm.app) [[ $undead_env[ITERM_SESSION_ID] == *:?* ]] && REPLY=iterm2-${undead_env[ITERM_SESSION_ID]#*:} ;;
      Apple_Terminal) [[ -n $undead_env[TERM_SESSION_ID] ]] && REPLY=terminal-${undead_env[TERM_SESSION_ID]##*:} ;;
      *) return 1 ;;
    esac
  fi
  [[ $REPLY =~ '^[A-Za-z0-9._-]+$' ]]
}

# This shell's own tab
undead_terminal_id() {
  emulate -L zsh
  undead_env=(TERM_PROGRAM "$TERM_PROGRAM" ITERM_SESSION_ID "$ITERM_SESSION_ID"
              TERM_SESSION_ID "$TERM_SESSION_ID" TMUX "$TMUX" TMUX_PANE "$TMUX_PANE" TTY "$TTY")
  undead_tab_id
}

# tmux panes. A pane's id (%N) means nothing once its server stops, so a pane is named after its server as well:
# tmux-<server start time>-<server pid>-<N>. A file in $UNDEAD_STATE/tmux/ under the same name says where the pane
# was: socket, server pid, server start time, session, window index, window name, whether tmux named the window
# itself (automatic-rename), pane index, and a last line "closed" once the user closed the pane while its server ran.
# When the server stops (reboot, kill-server), the first shell of each session in the next server on that socket
# opens that session's panes again, and each new pane's shell resumes its record like a restored terminal tab.
typeset -gA undead_tmux

undead_tmux_bin() {
  emulate -L zsh
  local f
  REPLY=$commands[tmux]
  [[ -n $REPLY ]] && return 0
  # A tmux server started by launchd hands its panes a bare PATH until the shell's rc files have run
  for f in /opt/homebrew/bin/tmux /usr/local/bin/tmux /opt/local/bin/tmux; do
    [[ -x $f ]] && { REPLY=$f; return 0 }
  done
  return 1
}

# Asks tmux where a pane is and fills undead_tmux. Usage: undead_tmux_query SOCKET PANE_ID
undead_tmux_query() {
  emulate -L zsh
  local out
  local -a f
  undead_tmux=()
  [[ $1 == /* && $2 == %<-> ]] || return 1
  undead_tmux_bin || return 1
  out=$($REPLY -S $1 display-message -p -t $2 \
    '#{pid}	#{start_time}	#{session_name}	#{window_index}	#{window_name}	#{automatic-rename}	#{pane_index}	#{pane_id}	#{pane_tty}	#{session_windows}	#{window_panes}	#{window_id}' \
    2>/dev/null) || return 1
  f=("${(@ps:\t:)out}")
  (( $#f == 12 )) && [[ $f[1] == <-> && $f[2] == <-> && $f[8] == $2 ]] || return 1
  undead_tmux=(socket $1 pid $f[1] start $f[2] session $f[3] window $f[4] name $f[5] auto $f[6] pane $f[7] id $f[8]
               tty $f[9] windows $f[10] panes $f[11] window_id $f[12])
}

# The id of a pane, checked against tmux: the pane must exist on that socket now, and when the caller knows its
# terminal, the pane must be that terminal (TMUX_PANE is inherited by whatever a pane starts, including apps).
# Usage: undead_tmux_pane_id SOCKET PANE_ID [TTY]
undead_tmux_pane_id() {
  emulate -L zsh
  REPLY=
  undead_tmux_query $1 $2 || return 1
  [[ -z $3 || $3 == $undead_tmux[tty] ]] || return 1
  REPLY=tmux-$undead_tmux[start]-$undead_tmux[pid]-${undead_tmux[id]#%}
}

# Saves where the pane in undead_tmux is, under its id. Usage: undead_tmux_note ID
undead_tmux_note() {
  emulate -L zsh
  local tmp=$UNDEAD_STATE/tmux/.tmp.$$
  zf_mkdir -p -m 700 $UNDEAD_STATE/tmux
  print -rl -- $undead_tmux[socket] $undead_tmux[pid] $undead_tmux[start] $undead_tmux[session] $undead_tmux[window] \
    $undead_tmux[name] $undead_tmux[auto] $undead_tmux[pane] > $tmp && zf_mv -f $tmp $UNDEAD_STATE/tmux/$1
}

# Opens a new pane for the record of pane ID in its tmux session and moves the record to that pane, whose shell then
# resumes it. The session is created when it doesn't exist, and with it the server when none runs on the socket.
# Panes that shared a window share one again, through undead_tmux_windows (old session:window -> new window).
# The caller holds the tmux lock. REPLY = the new pane's id. Usage: undead_tmux_place ID
typeset -gA undead_tmux_windows

undead_tmux_place() {
  emulate -L zsh
  local id=$1 tmux out new cwd slot sock session window name auto
  local -a side rec common named f
  [[ -r $UNDEAD_STATE/tmux/$id && -r $UNDEAD_STATE/tabs/$id ]] || return 1
  side=("${(@f)$(<$UNDEAD_STATE/tmux/$id)}")
  rec=("${(@f)$(<$UNDEAD_STATE/tabs/$id)}")
  (( $#side >= 8 && $#rec >= 3 )) || return 1
  sock=$side[1] session=$side[4] window=$side[5] name=$side[6] auto=$side[7]
  [[ $sock == /* && -n $session && $window == <-> ]] || return 1
  undead_tmux_bin || return 1
  tmux=$REPLY
  cwd=$rec[3]
  [[ -d $cwd ]] || cwd=$HOME
  slot=$sock:$session:$window
  common=(-d -c $cwd -e UNDEAD_TMUX_RESTORED=1 -P -F '#{pane_id}	#{window_id}')
  # A name tmux gave the window itself would stop following the running command if it were set by hand
  [[ $auto == 1 || -z $name ]] || named=(-n $name)
  if [[ -n $undead_tmux_windows[$slot] ]]; then
    out=$($tmux -S $sock split-window $common -t $undead_tmux_windows[$slot] 2>/dev/null)
  elif ! $tmux -S $sock has-session -t "=$session" 2>/dev/null; then
    out=$($tmux -S $sock new-session $common $named -s $session 2>/dev/null)
  else
    # Its old place if that is free, else the next free one
    out=$($tmux -S $sock new-window $common $named -t "=$session:$window" 2>/dev/null) ||
      out=$($tmux -S $sock new-window $common $named -t "=$session:" 2>/dev/null)
  fi
  f=("${(@ps:\t:)out}")
  [[ $f[1] == %<-> ]] || { undead_log "tmux[$$] could not open a pane for $id in $session"; return 1 }
  undead_tmux_windows[$slot]=$f[2]
  undead_tmux_pane_id $sock $f[1] || return 1
  new=$REPLY
  undead_tmux_note $new
  zf_mv -f $UNDEAD_STATE/tabs/$id $UNDEAD_STATE/tabs/$new
  zf_rm -f $UNDEAD_STATE/tmux/$id
  undead_log "tmux[$$] restoring $rec[1] $rec[2] of $session:$window in a new pane: $id -> $new"
  REPLY=$new
}

# Serialises everything that moves tmux records, so a pane is restored once however many shells start at once.
# Usage: undead_tmux_lock / undead_tmux_unlock
undead_tmux_lock() {
  zmodload -F zsh/system b:zsystem 2>/dev/null || return 1
  zf_mkdir -p -m 700 $UNDEAD_STATE/tmux
  : >> $UNDEAD_STATE/tmux.lock
  typeset -g _undead_tmux_fd
  zsystem flock -t 10 -f _undead_tmux_fd $UNDEAD_STATE/tmux.lock 2>/dev/null
}
undead_tmux_unlock() { [[ -n $_undead_tmux_fd ]] && zsystem flock -u $_undead_tmux_fd; _undead_tmux_fd= }

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
      (TERM_PROGRAM=*|ITERM_SESSION_ID=*|TERM_SESSION_ID=*|TMUX=*|TMUX_PANE=*) undead_env[${w%%=*}]=${w#*=} ;;
    esac
  done
  (( ${#undead_env} ))
}

# The folder a process is in, read with lsof (about 80 ms). A tab shell stays in the folder it started the agent from
# for as long as the agent runs, while the cwd the agent reports follows its Bash tool's `cd`. lsof is in /usr/sbin,
# which a scrubbed PATH lacks. Usage: undead_cwd_of PID -> REPLY
undead_cwd_of() {
  emulate -L zsh
  local line
  REPLY=
  [[ $1 == <-> ]] || return 1
  for line in ${(f)"$(${commands[lsof]:-/usr/sbin/lsof} -a -p $1 -d cwd -Fn 2>/dev/null)"}; do
    [[ $line == n* ]] && { REPLY=${line#n}; break }
  done
  [[ $REPLY == /* && -d $REPLY ]] || { REPLY=; return 1 }
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
