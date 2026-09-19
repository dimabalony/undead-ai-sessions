# Security

undead runs on your Mac as you. It edits `~/.zshrc`, `~/.claude/settings.json` and `~/.codex/hooks.json`, keeps its
state under `~/.local/state/undead`, and starts `claude` / `codex` with flags it read from your own command line. It
opens no network connection except when you run `install.sh` or `undead upgrade`, which download a release from GitHub.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead:
**[Report a vulnerability](https://github.com/dimabalony/undead-ai-sessions/security/advisories/new)**
(Security tab › Report a vulnerability).

Useful in a report: the undead version (`undead version`), macOS and terminal, what an attacker needs to control
(a file, an environment variable, a session record), and what they gain.

You'll get an answer within a few days. Fixes ship as a new release; the advisory is published with it.

## Supported versions

The latest release. `undead upgrade`, `brew upgrade undead` or re-running the installer gets you there.
