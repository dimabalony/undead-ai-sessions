# undead: brings Claude Code / Codex sessions back in terminal tabs restored after quitting the terminal or rebooting.
# Sourced from ~/.zshrc by `undead install`. Supported terminals: iTerm2 (tabs and split panes) and Terminal.app.
#
# The terminal gives every tab an id and restores it with the tab. This file registers the tab's shell, lib/hook records
# which agent session runs in it, and when the terminal restores the tab this file resumes that session in place.

[[ -o interactive && -z $UNDEAD_DISABLE ]] || return 0
source "${${(%):-%x}:A:h}/common.zsh" || return 0
undead_terminal_id || return 0

typeset -g _undead_id=$REPLY
typeset -g _undead_tab=$UNDEAD_STATE/tabs/$REPLY
typeset -g _undead_pending= _undead_scheduled= _undead_active= _undead_marker=
typeset -g UNDEAD_FORGET_DELAY=${UNDEAD_FORGET_DELAY:-10}
typeset -g UNDEAD_SUPPORT_PAUSE=${UNDEAD_SUPPORT_PAUSE:-10}

() {
  emulate -L zsh
  local f
  zf_mkdir -p -m 700 $UNDEAD_STATE $UNDEAD_STATE/tabs $UNDEAD_STATE/shells
  for f in $UNDEAD_STATE/shells/<->(N); do
    kill -0 ${f:t} 2>/dev/null || zf_rm -f $f $f.cmd
  done
  # Tabs closed while an agent was running never come back
  for f in $UNDEAD_STATE/tabs/*(N.m+30); do
    zf_rm -f $f
  done
  print -rl -- $_undead_id "$(ps -o lstart= -p $$)" > $UNDEAD_STATE/shells/$$
  # Another live shell for this tab (e.g. a nested zsh) already owns the session
  [[ -r $_undead_tab ]] && ! undead_live_shell_for $_undead_id && _undead_pending=1
  # Claude Code marks every process it starts, and a Claude session that inherits the mark saves no transcript. Under
  # an agent that is expected; in a tab shell it means the terminal app itself was launched from a Claude session.
  [[ -n $CLAUDE_CODE_CHILD_SESSION$CLAUDECODE ]] && ! undead_under_agent && _undead_marker=1
}

_undead_precmd() {
  local st=$?
  emulate -L zsh
  if [[ -n $_undead_marker ]]; then
    _undead_marker=
    print -r -- $'\e[33m'"undead: this terminal inherited Claude Code's session marker; Claude sessions started here" \
      "don't save transcripts and can't be resumed. Launch the terminal from the Dock or Finder, or run:" \
      "unset CLAUDE_CODE_CHILD_SESSION CLAUDECODE"$'\e[0m'
    undead_log "zsh[$$] tab $_undead_id inherited Claude Code's session marker: its Claude sessions save no transcript"
  fi
  if [[ -n $_undead_pending ]]; then
    _undead_pending=
    _undead_resume || return 0
    st=$REPLY
  fi
  # Only a shell that ran something since it started can have run the agent in the record
  [[ -n $_undead_active && -e $_undead_tab ]] || return 0
  # Killed by a signal or only suspended: keep it for the next restore
  local -a suspended=(${(M)${(v)jobstates}:#suspended*})
  (( st == 129 || st == 137 || st == 143 || ${#suspended} )) && return 0

  # When the terminal quits, the agent can exit before this shell is killed, so the session is forgotten only if the
  # shell is still alive a bit later and no new session has replaced the record in the meantime
  local tab=$_undead_tab inode=$(zstat +inode $_undead_tab 2>/dev/null)
  [[ $_undead_scheduled == $inode ]] && return 0
  _undead_scheduled=$inode
  undead_log "zsh[$$] agent in tab $_undead_id exited with $st, forgetting it in ${UNDEAD_FORGET_DELAY}s if the tab stays open"
  {
    sleep $UNDEAD_FORGET_DELAY
    if [[ $(zstat +inode $tab 2>/dev/null) != $inode ]]; then
      :
    elif ! kill -0 $$ 2>/dev/null; then
      undead_log "zsh[$$] kept tab ${tab:t}: the tab closed"
    else
      zf_rm -f $tab
      undead_log "zsh[$$] forgot tab ${tab:t}"
    fi
  } </dev/null >/dev/null 2>&1 &!
}

_undead_resume() {
  emulate -L zsh
  local -a rec=("${(@f)$(<$_undead_tab)}") cmd
  if ! undead_resume_command $_undead_tab || ! cd -q -- $rec[3] 2>/dev/null; then
    print -r -- $'\e[33m'"undead: could not resume ${(q-)rec[1]} session ${(q-)rec[2]} in ${(q-)rec[3]}"$'\e[0m'
    undead_log "zsh[$$] could not resume tab $_undead_id: ${(j: :)${(@q-)rec[1,3]}}"
    zf_rm -f $_undead_tab
    return 1
  fi
  cmd=("${(@)reply}")
  _undead_active=1
  if [[ -n $undead_resume_fresh ]]; then
    # Nothing to resume: the agent's own error would leave a bare prompt, so the tab gets a fresh agent instead
    if [[ $rec[1] == claude ]]; then
      print -r -- $'\e[33m'"undead: claude session $rec[2] was never saved by Claude (no message yet, or its" \
        "transcript saving was off): starting claude fresh in ${(D)PWD}"$'\e[0m'
    else
      print -r -- $'\e[33m'"undead: codex session $rec[2] has no saved rollout: starting codex fresh in ${(D)PWD}"$'\e[0m'
    fi
    undead_log "zsh[$$] restarting tab $_undead_id: ${(j: :)${(@q-)cmd}} (no transcript for $rec[2])"
  else
    print -r -- $'\e[36m'"↻ undead: resuming $rec[1] session $rec[2] in ${(D)PWD}"$'\e[0m'
    undead_log "zsh[$$] resuming tab $_undead_id: ${(j: :)${(@q-)cmd}}"
    _undead_support_message
  fi
  print -rs -- "${(j: :)${(@q-)cmd}}"
  # The hook reads the flags to replay from here, exactly as for a typed command
  print -r -- "${(j: :)${(@q-)cmd}}" > $UNDEAD_STATE/shells/$$.cmd
  $cmd
  REPLY=$?
}

# An occasional one-line support message, shown in one tab per restore at the 3rd, 10th, 25th, 50th restore and then
# every 50th, and held on screen for ten seconds, since the agent's full-screen UI covers it the moment it starts.
# `undead donate off` hides it.
_undead_support_message() {
  emulate -L zsh
  [[ -z $UNDEAD_NO_DONATE ]] || return 0
  undead_config donate && [[ $REPLY == off ]] && return 0
  zmodload -F zsh/system b:zsystem 2>/dev/null || return 0
  local file=$UNDEAD_STATE/restores fd count last shown=
  : >> $file
  zsystem flock -t 2 -f fd $file 2>/dev/null || return 0
  local -a data=("${(@f)$(<$file)}")
  count=${data[1]:-0} last=${data[2]:-0}
  # All tabs restored by the same relaunch count once
  if (( EPOCHSECONDS - last >= 120 )); then
    (( count++ ))
    print -rl -- $count $EPOCHSECONDS > $file
    if (( count == 3 || count == 10 || count == 25 || count == 50 || (count > 50 && count % 50 == 0) )); then
      print -r -- $'\e[35m'"♥ undead has brought your AI sessions back $count times. If it saves you time, star it or support it: $UNDEAD_REPO"$'\e[0m'
      print -r -- $'\e[2m'"  (hide this message: undead donate off${UNDEAD_SUPPORT_PAUSE:+ · resuming in $UNDEAD_SUPPORT_PAUSE s})"$'\e[0m'
      shown=1
    fi
  fi
  zsystem flock -u $fd
  (( shown && UNDEAD_SUPPORT_PAUSE > 0 )) && sleep $UNDEAD_SUPPORT_PAUSE
  return 0
}

# Running another command in the tab means the agent was closed for good. Commands that start an agent are kept so the
# hook can replay their flags on resume.
_undead_preexec() {
  emulate -L zsh
  _undead_active=1
  local -a suspended=(${(M)${(v)jobstates}:#suspended*})
  if [[ -e $_undead_tab ]] && (( ! ${#suspended} )); then
    zf_rm -f $_undead_tab
    undead_log "zsh[$$] forgot tab $_undead_id: new command started"
  fi
  if [[ $3 == *(claude|codex)* ]]; then
    print -r -- $3 > $UNDEAD_STATE/shells/$$.cmd
  else
    zf_rm -f $UNDEAD_STATE/shells/$$.cmd
  fi
}

_undead_zshexit() { zf_rm -f $UNDEAD_STATE/shells/$$ $UNDEAD_STATE/shells/$$.cmd }

# Last in line, so a prompt theme has finished drawing before a resume prints anything. Every precmd function sees the
# same $?, so the order doesn't affect the exit status we read.
() {
  emulate -L zsh
  precmd_functions=(${precmd_functions:#_undead_precmd} _undead_precmd)
  preexec_functions=(${preexec_functions:#_undead_preexec} _undead_preexec)
  zshexit_functions=(${zshexit_functions:#_undead_zshexit} _undead_zshexit)
}
