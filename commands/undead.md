---
description: Run undead, the tool that brings Claude Code and Codex sessions back in restored terminal tabs, or set it up if it isn't installed
argument-hint: '[doctor|list|reopen|forget|log|install|uninstall]'
disable-model-invocation: true
allowed-tools: Bash(undead:*), Bash(command -v undead), AskUserQuestion
---

Subcommand: `$ARGUMENTS` (use `doctor` when empty).

undead is a separate zsh tool; this plugin is only a wrapper for it. The resume itself happens in the shell when a
terminal restores a tab, so it can't be done from here.

Find the installed CLI with `command -v undead`, then `~/.local/bin/undead`. A copy under this plugin's own directory
doesn't count: undead works only after its installer has set up the shell and the hooks.

**Installed:** run `undead $ARGUMENTS`, then explain the result in a few lines — for `doctor`, which check failed and
the exact setting that fixes it; for `list`, which saved sessions still have an open tab; for `log`, what the last
`recorded` / `resuming` / `forgot` / `skip` decisions mean.

**Not installed:** don't run the plugin's copy. Say what the installer touches:

- `~/.zshrc`: one marked block
- `~/.claude/settings.json`: a SessionStart and a SessionEnd hook
- `~/.codex/hooks.json`: a SessionStart hook
- `~/.local/share/undead` and `~/.local/bin/undead`: the program itself

Ask whether to install it. Only if the user agrees, run:

```sh
curl -fsSL https://raw.githubusercontent.com/dimabalony/undead-ai-sessions/main/install.sh | sh
```

Then tell them to open a new terminal tab (tabs that are already open don't have undead yet), and that the next time
they start `codex` it asks *Hooks need review* → choose **Trust all and continue**.
