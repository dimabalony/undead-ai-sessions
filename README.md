# undead-ai-sessions

**Your AI sessions refuse to die.**

You run Claude Code and Codex in a bunch of terminal tabs. Then you quit the terminal, macOS installs an update, or the
laptop reboots. The tabs come back empty, and you're left guessing which `claude --resume` or `codex resume` belonged
where.

With undead, every restored tab continues its exact conversation by itself:

```text
Session Contents Restored on 15 Sep 2026 at 18:32
↻ undead: resuming claude session 51b570c1-11cd-4e1d-9666-04b230a03674 in ~/Developer/my-app
```

No command to run, no picker, no guessing. Each tab gets back its own session, in its folder, with the flags you
started it with.

## Install

macOS with zsh (the default shell). Requires iTerm2 or Terminal.app.

```sh
git clone https://github.com/dimabalony/undead-ai-sessions.git
cd undead-ai-sessions
./install.sh
```

Or without cloning:

```sh
curl -fsSL https://raw.githubusercontent.com/dimabalony/undead-ai-sessions/main/install.sh | sh
```

Then:

1. **Open a new tab.** Tabs that were already open don't have undead yet.
2. **Codex only:** the next time you start `codex` it says *Hooks need review*. Choose **Trust all and continue**.
3. Run `undead doctor` to check that everything is set up.

## How it works

1. iTerm2 and Terminal.app give every tab (and every iTerm2 split pane) an id, and keep that id when they restore
   windows after a quit or a reboot.
2. Each new shell registers itself: "this process is the shell of tab X".
3. When Claude Code or Codex starts a session, a `SessionStart` hook walks up the process tree to that shell and saves
   *tab X runs session Y in folder Z, started with these flags*.
4. When the terminal restores tab X, its new shell finds that entry and runs `claude --resume Y` or `codex resume Y` in
   folder Z.

undead forgets a session when you really close it: right away when you exit Claude, when you run another command in
the tab, or 10 seconds after the agent exits if the tab is still open. When the terminal quits, the shell is killed
before any of that happens, so the session is kept.

It doesn't poll, run a daemon, or type into a running agent. The one exception is `undead reopen`, which asks
macOS for permission to open a new tab in your terminal and type the resume command there.

## What's supported

| | |
|---|---|
| Terminals | iTerm2 (tabs and split panes), Terminal.app |
| Agents | Claude Code, Codex CLI |
| Shell | zsh |

Ignored on purpose, because they aren't the session that belongs to the tab:

- agents started by other agents (for example `claude -p` run inside Claude)
- agents inside tmux
- Codex's internal sessions (auto-review, memory)
- other apps that inherited a terminal's tab id (for example VS Code's terminal opened from iTerm2)

### Flags that come back

Only flags that make sense for a resumed session are replayed, and only if you used them:

- **Claude Code:** `--model`, `--permission-mode`, `--dangerously-skip-permissions`, `--effort`, `--add-dir`,
  `--settings`, `--mcp-config`, `--agent`, `--allowedTools`, `--system-prompt`, `--append-system-prompt`, `--chrome`
  and a few more
- **Codex:** `-m`, `-p`, `-s`, `-a`, `-c`, `--yolo`, `--dangerously-bypass-approvals-and-sandbox`, `--search`,
  `--add-dir`, `--enable`, `--disable`

Prompts, `--print`, `--continue` and `--worktree` are never replayed. Codex sessions resume with its update check turned
off, so an update notice doesn't block the restored tab.

## Commands

```text
undead install [--no-claude] [--no-codex] [--no-shell]   set up (safe to run again)
undead uninstall [--purge]                               remove everything it added
undead doctor                                            check that restores will work
undead list                                              saved sessions and whether their tab is open
undead reopen [N|ID|--all]                               resume a session whose tab is gone, in a new tab
undead forget [N|ID|--all]                               drop saved sessions
undead log [-f]                                          what undead did, and why
undead donate [on|off]                                   show or hide the occasional support message
```

## Things to know

- **macOS must restore windows.** In *System Settings › Desktop & Dock*, turn off *Close windows when quitting an
  application*. In iTerm2, *Settings › General › Startup › Window restoration policy* should be *Use System Window
  Restoration Setting*. `undead doctor` checks both.
- **Only a normal quit counts in Terminal.app.** After a force quit or a crash, Terminal.app opens fresh windows
  instead of restoring them (iTerm2 restores either way).
- **Closed a tab by mistake?** Tabs closed with ⌘W don't come back, but their session is still saved:
  `undead reopen` opens it in a new tab.
- **Claude asks to trust your home folder every time.** That's Claude Code: it never saves trust for the home folder.
  Start agents from a project folder instead.
- **Agent teams:** teammates can't be restored. Claude Code itself doesn't restore teammates when a lead session is
  resumed; ask the lead to spawn them again.
- **Not supported yet:** bash, fish, tmux, Ghostty, Warp, WezTerm, Kitty.

## Troubleshooting

Start with `undead doctor`, then `undead log`. Every decision is logged: `recorded`, `resuming`, `forgot` and `skip`,
each with its reason.

## Privacy

Everything stays on your Mac. undead touches:

- `~/.zshrc`: one marked block
- `~/.claude/settings.json`: a `SessionStart` and a `SessionEnd` hook
- `~/.codex/hooks.json`: a `SessionStart` hook
- `~/.local/state/undead`: saved sessions, the log, and backups of the files above
- `~/.config/undead`: whether the support message is hidden
- `~/.local/share/undead` and `~/.local/bin/undead`: the program itself

`undead uninstall --purge` removes all of it, including the program itself.

## Support

undead is free and MIT licensed. If it saves you time, a donation helps keep it alive:

- **USDT (Tron / TRC20):** `TL8Ph6ydv5pwHdBJXTQDakDZLN1MwYoqiQ`

Bug reports and pull requests are welcome too.

## Development

```sh
test/run          # all tests, in a sandbox that never touches your real config
test/run shell    # one suite: cli, flags, hook or shell
```

## License

MIT
