# Changelog

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
