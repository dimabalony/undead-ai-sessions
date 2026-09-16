source ${0:A:h}/helpers.zsh

U=$ROOT/bin/undead
hooks_in() { REPLY=$(osascript -l JavaScript $ROOT/lib/json-hooks.js find $1) }
count_in() { grep -c -- "$2" $1 2>/dev/null }

# osascript is shadowed so `undead install` can't ask a real terminal for its tabs; -l JavaScript still reaches the
# real one, which lib/json-hooks.js needs
mkdir -p $SANDBOX/bin
print -l -- '#!/bin/sh' 'case "$1" in -l) exec /usr/bin/osascript "$@" ;; esac' 'cat >/dev/null 2>&1' > $SANDBOX/bin/osascript
chmod +x $SANDBOX/bin/osascript
export PATH=$SANDBOX/bin:$PATH

mkdir -p $HOME/.claude $HOME/.codex
cat > $HOME/.claude/settings.json <<'EOF'
{
  "model": "opus",
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "/usr/local/bin/other-tool"}]}]
  }
}
EOF
print -l -- 'export PATH="$HOME/bin:$PATH"' '' 'alias ll="ls -la"' > $HOME/.zshrc

print -r -- "install"
$U install > $SANDBOX/out 2>&1
check "exits successfully" test $? -eq 0
check "adds one block to ~/.zshrc" test "$(count_in $HOME/.zshrc '# >>> undead >>>')" -eq 1
check "keeps the existing ~/.zshrc lines" has $HOME/.zshrc 'alias ll="ls -la"'
hooks_in $HOME/.claude/settings.json
check "adds Claude SessionStart and SessionEnd hooks" test "${#${(f)REPLY}}" -eq 2
check "keeps other Claude hooks" has $HOME/.claude/settings.json /usr/local/bin/other-tool
check "keeps other Claude settings" has $HOME/.claude/settings.json '"model": "opus"'
hooks_in $HOME/.codex/hooks.json
check "adds the Codex SessionStart hook" test "$REPLY" = "SessionStart '$ROOT/lib/hook' codex start # undead"
check "backs up the files it changed" test -n "$(print $STATE/backups/settings.json.*(N))"
check "protects the sessions already running" has $SANDBOX/out "Sessions already running"

cp $HOME/.zshrc $SANDBOX/zshrc.first
$U install > /dev/null 2>&1
check "running install again changes nothing in ~/.zshrc" cmp -s $HOME/.zshrc $SANDBOX/zshrc.first
hooks_in $HOME/.claude/settings.json
check "running install again doesn't duplicate hooks" test "${#${(f)REPLY}}" -eq 2

print -r -- "doctor"
TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:DOC $U doctor > $SANDBOX/out 2>&1
check "reports the hooks as installed" has $SANDBOX/out "SessionEnd hook installed"
check "reports the Codex hook as installed" eval '[[ "$(sed -n "/^Codex/,/^Saved/p" $SANDBOX/out)" == *"SessionStart hook installed"* ]]'
check "doesn't report any broken hook" eval '! has $SANDBOX/out "points to a missing file"' 
check "notices Codex hasn't trusted the hook yet" has $SANDBOX/out "hasn't trusted the hook yet"
print -r -- "[hooks.state.\"$HOME/.codex/hooks.json:session_start:0:0\"]" > $HOME/.codex/config.toml
print -r -- 'trusted_hash = "sha256:abc"' >> $HOME/.codex/config.toml
TERM_PROGRAM=iTerm.app ITERM_SESSION_ID=w0t0p0:DOC $U doctor > $SANDBOX/out 2>&1
check "sees when Codex trusted the hook" has $SANDBOX/out "Codex has trusted a hook"

print -r -- "list, forget, reopen, donate"
print -rl -- claude 11111111-2222-3333-4444-555555555555 $HOME/project > $STATE/tabs/iterm2-L1
print -rl -- codex 019e3f51-cebd-77d2-b342-c1f5f1bd1f60 $HOME/other > $STATE/tabs/iterm2-L2
$U list > $SANDBOX/out
check "list shows saved sessions" has $SANDBOX/out 019e3f51-cebd-77d2-b342-c1f5f1bd1f60
check "  ...with a closed tab" has $SANDBOX/out closed
TERM_PROGRAM=WarpTerminal $U reopen 11111111-2222-3333-4444-555555555555 > $SANDBOX/out
check "reopen in an unsupported terminal prints the command to run" has $SANDBOX/out "cd -- $HOME/project && claude --resume 11111111-2222-3333-4444-555555555555"
check "  ...and keeps the session" test -f $STATE/tabs/iterm2-L1
$U forget 11111111-2222-3333-4444-555555555555 > /dev/null
check "forget by id drops that session" missing $STATE/tabs/iterm2-L1
check "  ...and only that one" test -f $STATE/tabs/iterm2-L2
$U forget --all > /dev/null
check "forget --all drops the rest" test -z "$(print $STATE/tabs/*(N))"
$U donate off > /dev/null
check "donate off is saved" has $UNDEAD_CONFIG_DIR/config donate=off
$U donate on > /dev/null
check "donate on is saved" has $UNDEAD_CONFIG_DIR/config donate=on

print -r -- "uninstall"
$U uninstall > /dev/null 2>&1
check "removes the ~/.zshrc block" test "$(count_in $HOME/.zshrc undead)" -eq 0
check "restores ~/.zshrc as it was" cmp -s $HOME/.zshrc =(print -l -- 'export PATH="$HOME/bin:$PATH"' '' 'alias ll="ls -la"')
hooks_in $HOME/.claude/settings.json
check "removes the Claude hooks" test -z "$REPLY"
check "keeps other Claude hooks" has $HOME/.claude/settings.json /usr/local/bin/other-tool
check "deletes a hooks.json that only had undead in it" missing $HOME/.codex/hooks.json

print -r -- "dotfiles and broken files"
mkdir -p $SANDBOX/dotfiles && mv $HOME/.zshrc $SANDBOX/dotfiles/zshrc && ln -s $SANDBOX/dotfiles/zshrc $HOME/.zshrc
$U install --no-claude --no-codex > /dev/null 2>&1
check "a symlinked ~/.zshrc stays a symlink" test -L $HOME/.zshrc
check "  ...and the block lands in the real file" has $SANDBOX/dotfiles/zshrc '# >>> undead >>>'
mkdir -p $SANDBOX/dotfiles2
mv $HOME/.claude/settings.json $SANDBOX/dotfiles2/settings.json
ln -s $SANDBOX/dotfiles2/settings.json $HOME/.claude/settings.json
$U install --no-shell --no-codex > /dev/null 2>&1
check "a symlinked settings.json stays a symlink" test -L $HOME/.claude/settings.json
check "  ...and the hooks land in the real file" has $SANDBOX/dotfiles2/settings.json undead

print -l -- 'alias k=kubectl' '# >>> undead >>>' 'source /somewhere/undead.zsh' > $SANDBOX/dotfiles/zshrc
$U install --no-claude --no-codex > $SANDBOX/out 2>&1
check "an undead block without its end marker stops install" test $? -ne 0
check "  ...and the rest of ~/.zshrc is untouched" has $SANDBOX/dotfiles/zshrc 'alias k=kubectl'

print -r -- '{ "hooks": ' > $HOME/.claude/settings.json
$U install --no-shell --no-codex > $SANDBOX/out 2>&1
check "a broken settings.json makes install fail" test $? -ne 0
check "  ...and is left untouched" test "$(<$HOME/.claude/settings.json)" = '{ "hooks": '


print -r -- "purge"
# start from files undead can safely touch again
print -l -- 'alias k=kubectl' > $SANDBOX/dotfiles/zshrc
print -r -- '{}' > $HOME/.claude/settings.json
mkdir -p $HOME/.local/share/undead/bin $HOME/.local/bin
: > $HOME/.local/share/undead/bin/undead
ln -sf $HOME/.local/share/undead/bin/undead $HOME/.local/bin/undead
$U uninstall --purge > /dev/null 2>&1
check "purge deletes saved sessions" missing $STATE/tabs
check "purge removes the installed copy too" wait_until 5 eval '[[ ! -e $HOME/.local/share/undead && ! -L $HOME/.local/bin/undead ]]'

finish
