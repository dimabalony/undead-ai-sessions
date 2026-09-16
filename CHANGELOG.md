# Changelog

## 0.3.3

- A restored tab whose session was never saved (quit before its first message, or run with Claude Code's transcript
  saving off) starts the agent fresh in its folder with its flags and says why, instead of stopping at "No
  conversation found"; `undead reopen` does the same
- A terminal that inherited Claude Code's session marker (`CLAUDE_CODE_CHILD_SESSION`), which turns off transcript
  saving for every Claude session started in it, is called out in each new tab and by `undead doctor`, with the fix

## 0.3.2

- `undead upgrade` and `install.sh` find the latest release without the GitHub API, whose unauthenticated limit of 60
  requests an hour per network address blocked an office upgrade; rate limits are named when they do happen

## 0.3.1

- `undead doctor` finds the tab's shell when it runs inside an agent (from Claude Code's Bash tool it used to warn
  "started before undead was installed" about a shell that was fine), and points at `undead adopt` when it isn't
- The plugin's `/undead` is a skill, so the bare name resolves; `/undead:undead` still works

## 0.3.0

- `undead adopt` now finds a tab through the agent's own environment instead of AppleScript, so it covers Terminal.app
  as well as iTerm2 and needs no automation permission
- Codex sessions are adopted too, identified by the rollout a running Codex holds open
- `undead upgrade [--check]` updates undead itself to the latest release in place, leaving the hooks alone;
  `install.sh` installs the latest release instead of `main`. Installs older than 0.3.0 have no `upgrade` command:
  re-run the install command once
- The Claude Code plugin says when it ships a newer undead than the one installed

## 0.2.0

- `undead adopt` records the Claude Code sessions that are already running, so installing undead no longer means
  restarting every tab; `undead install` runs it last and says how many it adopted
- Sessions it can't adopt are named, with the reason: Codex saves no pid or tty, and Terminal.app tabs have no id

## 0.1.0

First release.

- Restored iTerm2 tabs and split panes, and Terminal.app tabs, resume their Claude Code or Codex session in place
- Sessions are matched to tabs through the process tree, so nested agents, tmux and Codex internal sessions don't
  overwrite a tab's session
- A session you close is forgotten; a session killed by quitting the terminal is kept
- Replays the flags a session was started with
- `undead install`, `uninstall`, `doctor`, `list`, `reopen`, `forget`, `log`, `donate`
- Claude Code plugin: a `/undead` command, a once-a-day reminder when the CLI isn't installed, and the repo doubles as
  the plugin's marketplace
