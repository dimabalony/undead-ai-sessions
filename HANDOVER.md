# Handover

Everything a new session (or a new contributor) needs to pick this up. Written 2026-09-16.

## The problem this solves

Dmitry runs several Claude Code and Codex sessions in iTerm2 tabs. Quitting iTerm2 (⌘Q) or rebooting kills the agent
processes. iTerm2 brings the tabs back, but each one is an empty shell, and finding the right `claude --resume <id>` per
tab meant guessing. `claude --continue` is no help when several tabs share one directory.

## How it works

1. iTerm2 gives each tab and split pane a GUID in `ITERM_SESSION_ID` and **restores the same GUID** when it restores
   windows (verified in iTerm2's source, `PTYSession.m`: the session adopts `SESSION_ARRANGEMENT_GUID` from the saved
   arrangement, and `ITERM_SESSION_ID` is built from it). Terminal.app does the same through `TERM_SESSION_ID`.
2. `lib/undead.zsh`, sourced from `~/.zshrc`, registers the tab's shell in `~/.local/state/undead/shells/<pid>`
   (tab id + the shell's start time, which makes a reused pid detectable).
3. `lib/hook` runs as a `SessionStart` hook in both agents. It climbs the process tree hook → agent (→ `node` for
   Codex's launcher) → the shell that started the agent. If that shell is registered, it writes
   `~/.local/state/undead/tabs/<tab id>`: tool, session id, cwd, and the flags to replay.
4. When the terminal restores the tab, the new shell finds that file and runs `claude --resume` / `codex resume` in the
   saved directory, in the same tab.

## Decisions, and why

- **Match by process tree, not env vars.** Codex scrubs the environment before running hooks (`env_clear()` plus
  `shell_environment_policy`), so a hook can't read `ITERM_SESSION_ID`. macOS also blocks reading another process's
  environment. Hence the pid-file registry.
- **Ignore agents that aren't the tab's own session:** nested `claude -p` started by another agent, tmux panes, Codex's
  internal sessions (its rollout header's `source` is not `"cli"`), and apps that inherited a tab id (VS Code's
  terminal). Otherwise they overwrite the tab's real session.
- **Forgetting is the hard part.** The first version deleted the record as soon as the agent exited. On ⌘Q the agent
  exits *before* the shell is killed, so records were wiped and tabs came back empty — this was the bug the user hit.
  Now: Claude's `SessionEnd` with reason `prompt_input_exit`/`logout` forgets immediately (measured: a hangup or a
  terminal that disappears both report `other`, so they are safe); running another command in the tab forgets; and
  otherwise a detached timer forgets 10 s later, but only if the shell is still alive and the record's inode is
  unchanged. Codex's `SessionEnd` reason is hardcoded to `"other"` in 0.154, so it relies on the timer.
- **Only suspended jobs block forgetting**, not any background job (`${#jobstates}` counts running jobs too).
- **Replay flags from the command line**, captured in `preexec`, filtered through an allowlist, and validated again when
  resuming. Values containing spaces after a multi-value flag are dropped, so a prompt is never re-submitted.
- **No daemon, no polling, no AppleScript typing** (except `undead reopen`, which the user invokes).
- **No jq or python dependency**: hooks parse JSON with `plutil`, the CLI edits JSON through
  `osascript -l JavaScript` (`lib/json-hooks.js`), both part of macOS.

## Verified facts (don't re-litigate without re-testing)

- iTerm2 3.7.2 has a Claude Code integration (status, workgroups, code review) but **no session resume**.
- iTerm2 sends `SIGHUP` to the shell's process group on quit (`iTermMultiServerJobManager.m`).
- Claude Code `SessionEnd` reasons, measured with a real session: `/exit` → `prompt_input_exit`; pty closed → `other`;
  SIGHUP to the shell's group → `other`.
- Codex 0.154: hooks are a stable feature, live in `~/.codex/hooks.json`, and must be trusted once per hook command
  ("Hooks need review" → "Trust all and continue"); trust is a hash recorded in `config.toml` under `[hooks.state]`.
- Codex sub-agents fire `SubagentStart`, not `SessionStart`, so they can't be confused with the tab's session.
- Terminal.app restores tab ids after a **normal** quit, not after a force quit (measured both ways).
- Claude Code never persists trust for the home directory, so it asks every time an agent starts in `~`.
- Agent-team teammates cannot be restored: Claude Code's own docs list "no session resumption with in-process
  teammates", and a team's config is deleted when the lead exits.

## Layout

```
bin/undead         CLI: install, uninstall, doctor, list, reopen, forget, log, donate
lib/undead.zsh     shell integration (sourced from ~/.zshrc)
lib/hook           SessionStart/SessionEnd hook for both agents
lib/common.zsh     shared helpers: tab id, flag allowlist, resume command, log
lib/json-hooks.js  edits settings.json / hooks.json (macOS JavaScript, follows symlinks)
test/              4 suites, sandboxed HOME, fake agents, real pseudo-terminals
install.sh         copies into ~/.local/share/undead and runs `undead install`
Formula/undead.rb  Homebrew formula template for a personal tap
```

State: `~/.local/state/undead/{tabs,shells,log,restores,backups}`. A record is 3+ lines: tool, session id, cwd, then
one flag per line.

## Tests

`test/run` (about 45 s, 109 checks) or `test/run shell` for one suite. Everything runs against a throwaway `HOME`;
nothing touches the real config. Stand-in agents are symlinks to zsh, so `ps` shows them as `claude`/`codex`/`node`
and the process-tree logic is exercised for real. Pseudo-terminals come from `script`, which on macOS never passes
end-of-input, so `pty_shell` types `exit` and has a watchdog; `pty_bg` is for tests that kill the shell instead
(the quit case).

## Status

- Installed and in use on Dmitry's personal MacBook. The earlier prototype (`~/.config/agent-resume`) was migrated:
  saved sessions and live tab registrations were converted, and its hook file is now a forwarder so agents started
  before the switch keep being recorded. After the next iTerm2 restart, `~/.config/agent-resume` and
  `~/.local/state/agent-resume` can be deleted.
- Verified against the real binaries: Claude recorded with flags and forgotten on `/exit`; `codex exec` correctly
  skipped; `undead reopen` opened a real tab; Terminal.app restore confirmed.
- Reviewed by a separate agent; its confirmed findings are fixed and covered by tests.

## Left to do

1. `sudo xcodebuild -license accept` on the personal Mac — it blocks `git` (and `xcodebuild`), so the repo has no
   commits yet.
2. Fill in the wallet addresses in README.md → Support.
3. Publish as `dimabalony/undead-ai-sessions`, then install on the work MacBook and run `undead doctor`.
4. Optional: Homebrew tap (`Formula/undead.rb` has the steps), a demo GIF in the README.

## Ideas, not built

- bash and fish support; tmux (would need tmux-resurrect-style pane ids); Ghostty/WezTerm/Kitty (no restored tab id
  that we know of).
- Reopening a session whose tab never came back, automatically at login (today: `undead reopen`).
- Recording the agent's own `--name`, so `undead list` can show session names.

## Landscape (checked 2026-09-15)

Around 120 similar repos exist, nearly all from 2026 and most with no users. Closest by approach: `adrianschmidt`
(iTerm2, Claude only, login-time AppleScript typing), `kasimtasdemir` (iTerm2, Claude only, needs a daemon),
`2solarmax`/`clinch` (Warp). Terminals are shipping this natively: cmux, agterm, Clinch, and an open Warp PR. Nothing
free covers "iTerm2 + Claude + Codex, automatic, in the same tabs" — that is this project's niche. Two popular peers
(`Livshitz/claude-revive`, `Supersynergy/claude-session-restore`) silently add `--dangerously-skip-permissions` when
resuming; undead never adds a flag the user didn't use.
