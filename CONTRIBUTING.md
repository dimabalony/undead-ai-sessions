# Contributing

Run `zsh test/run` before opening a pull request; everything runs in a sandbox that never touches your real config.
CI runs the same suite on `macos-latest` for every push and pull request.

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
  exits *before* the shell is killed, so records were wiped and tabs came back empty — that is the bug undead exists to
  avoid. Now: Claude's `SessionEnd` with reason `prompt_input_exit`/`logout` forgets immediately (measured: a hangup or
  a terminal that disappears both report `other`, so they are safe); running another command in the tab forgets; and
  otherwise a detached timer forgets 10 s later, but only if the shell is still alive and the record's inode is
  unchanged. Codex's `SessionEnd` reason is hardcoded to `"other"` in 0.154, so it relies on the timer.
- **Only suspended jobs block forgetting**, not any background job (`${#jobstates}` counts running jobs too).
- **Replay flags from the command line**, captured in `preexec`, filtered through an allowlist, and validated again when
  resuming. Values containing spaces after a multi-value flag are dropped, so a prompt is never re-submitted.
- **No daemon, no polling, no AppleScript typing** (except `undead reopen`, which you run yourself).
- **No jq or python dependency**: hooks parse JSON with `plutil`, the CLI edits JSON through
  `osascript -l JavaScript` (`lib/json-hooks.js`), both part of macOS.
- **Adopt at install.** Installing undead used to leave every running agent unprotected until its tab was restarted.
  `undead adopt`, which `undead install` runs last, closes that gap. What can't be read is reported, never guessed
  from the working directory.
- **The tab comes from the agent's own environment**, read with `ps -E`. The agent inherited `TERM_PROGRAM` and
  `ITERM_SESSION_ID` / `TERM_SESSION_ID` from the shell that started it, so `undead_tab_id` applies the same rules to
  it as the shell applies to itself. Not the shell's own environment: a tab's login shell comes from `/usr/bin/login`
  and macOS won't show its environment. This replaced an AppleScript tty -> tab map, which needed automation
  permission and left out Terminal.app, whose dictionary exposes a tab's `tty` but no id.
- **Codex's session comes from the rollout it holds open.** Codex writes no pid and no tty anywhere, but a running one
  keeps its rollout files open, so `lsof` finds them and the header's `source` picks out the tab's conversation: the
  one that says `cli`, with the rest belonging to its subagents. Never the newest or the one whose `cwd` matches -- a
  months-old rollout resumed today is still the tab's session. Zero or several are reported rather than guessed.
- **The latest release is found through a redirect, not the API.** GitHub's unauthenticated API allows 60 calls an
  hour per network address, which everyone behind one office NAT shares; an upgrade failed in the field because of
  it. `https://github.com/<repo>/releases/latest` redirects to the tag page, so the tag is the last path segment of
  the effective URL, and the tarball comes from `codeload.github.com` -- neither is API-limited. The API is only the
  fallback, and when it does answer 403 the message names the rate limit and the wait instead of blaming the network.
- **`undead upgrade` installs releases, not `main`**, so an upgrade lands on a version someone tagged. It replaces
  `bin/` and `lib/` under the install directory and nothing else: the hook paths don't change, so there is no
  re-install and Codex doesn't ask to trust the hook again. Homebrew installs are sent to `brew upgrade`.
- **The plugin lives in `plugin/`, not at the repo root.** Claude Code appends a plugin's `bin/` to the Bash tool's
  PATH, so a root-level plugin would shadow `undead` for users who haven't installed it.

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
- `ps -Eww -o command= -p <pid>` prints a same-user process's inherited environment after its command line. It works
  for a running `claude` or `codex`, and not for the tab's login shell, which `/usr/bin/login` started.
- Codex stores no pid and no tty in any file: `~/.codex/session_index.jsonl` holds only `id`, `thread_name` and
  `updated_at`, and a rollout header has `cwd` and `originator` but nothing tying it to a process. It does hold its
  rollout files open, which is what `lsof` is for.
- A running Codex holds several rollouts open at once: its own conversation plus one per internal subagent. Only the
  header's `payload.source` separates them (`"cli"` against a `{"subagent": ...}` object).
- Terminal.app's AppleScript dictionary gives a tab a `tty` but no id of any kind. Its `TERM_SESSION_ID` is only
  readable from a process inside the tab. iTerm2's `unique id` of a session is the GUID `ITERM_SESSION_ID` carries.
- Agent-team teammates cannot be restored: Claude Code's own docs list "no session resumption with in-process
  teammates", and a team's config is deleted when the lead exits.

## Layout

```
bin/undead         CLI: install, uninstall, adopt, doctor, list, reopen, forget, log, donate
lib/undead.zsh     shell integration (sourced from ~/.zshrc)
lib/hook           SessionStart/SessionEnd hook for both agents
lib/common.zsh     shared helpers: tab id, flag allowlist, resume command, log
lib/json-hooks.js  edits settings.json / hooks.json (macOS JavaScript, follows symlinks)
test/              7 suites, sandboxed HOME, fake agents, real pseudo-terminals
install.sh         copies into ~/.local/share/undead and runs `undead install`
plugin/            Claude Code plugin: manifest, /undead command, nudge hook; the marketplace at the root points at it
```

State: `~/.local/state/undead/{tabs,shells,log,restores,backups}`. A record is 3+ lines: tool, session id, cwd, then
one flag per line.

## Tests

`test/run` (about 80 s, 240 checks) or `test/run shell` for one suite. Everything runs against a throwaway `HOME`;
nothing touches the real config. Stand-in agents are symlinks to zsh, so `ps` shows them as `claude`/`codex`/`node`
and the process-tree logic is exercised for real. Pseudo-terminals come from `script`, which on macOS never passes
end-of-input, so `pty_shell` types `exit` and has a watchdog; `pty_bg` is for tests that kill the shell instead
(the quit case).

## Releasing

1. Bump `UNDEAD_VERSION` in `lib/common.zsh` and `version` in `.claude-plugin/plugin.json` to the same value; the
   plugin test suite fails if they differ.
2. Add the release to `CHANGELOG.md`.
3. `git tag vX.Y.Z && git push --tags`, then create the GitHub release from the tag.
4. Update `Formula/undead.rb` in [github.com/dimabalony/homebrew-tap](https://github.com/dimabalony/homebrew-tap) with
   the new `url` and the `shasum -a 256` of
   `https://github.com/dimabalony/undead-ai-sessions/archive/refs/tags/vX.Y.Z.tar.gz`.

## Roadmap

The planned work lives in [the issues](https://github.com/dimabalony/undead-ai-sessions/issues): a demo GIF at the top
of the README (#1), `undead upgrade` so `curl | sh` installs update themselves (#2), VS Code and Cursor integrated
terminals (#3), bash and fish (#4), tmux panes (#5), and Ghostty, WezTerm, Kitty and Warp (#6).

Two ideas without an issue yet:

- Reopening a session whose tab never came back, automatically at login (today: `undead reopen`).
- Recording the agent's own `--name`, so `undead list` can show session names.
