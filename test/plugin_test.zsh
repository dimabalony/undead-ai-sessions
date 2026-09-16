source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

# The Claude Code plugin is glue around the CLI: manifests, one slash command, and a nudge hook.
unset XDG_STATE_HOME
M=$ROOT/.claude-plugin/marketplace.json
P=$ROOT/plugin/.claude-plugin
NUDGE=$ROOT/plugin/scripts/nudge
STAMP=$HOME/.local/state/undead-plugin/nudged

# plutil -lint only reads property lists on macOS 26, so JSON is checked the way lib/hook parses it
parses() { plutil -convert json -o /dev/null $1 }
json() { REPLY=$(plutil -extract $2 raw -o - - <$1 2>/dev/null) }
json_is() { json $1 $2; [[ $REPLY == $3 ]] || { print -r -- "    got: $REPLY"; return 1 } }

print -r -- "manifests"
check "plugin.json is valid JSON" parses $P/plugin.json
check "marketplace.json is valid JSON" parses $M
check "hooks.json is valid JSON" parses $ROOT/plugin/hooks/hooks.json
check "the plugin is called undead" json_is $P/plugin.json name undead
check "its version is UNDEAD_VERSION" json_is $P/plugin.json version $UNDEAD_VERSION
check "it names an author and a license" eval 'json $P/plugin.json author.name; [[ -n $REPLY ]] && json_is $P/plugin.json license MIT'
check "the marketplace is called undead-ai-sessions" json_is $M name undead-ai-sessions
check "it lists the undead plugin" json_is $M plugins.0.name undead
check "...from the plugin/ subdirectory" json_is $M plugins.0.source ./plugin

print -r -- "slash command"
CMD=$ROOT/plugin/commands/undead.md
check "plugin/commands/undead.md exists" test -f $CMD
line $CMD 1
check "it opens with frontmatter" test "$REPLY" = ---
check "the frontmatter has a description" eval 'grep -q "^description: ." $CMD'
check "...and an argument hint" eval 'grep -q "^argument-hint: ." $CMD'
check "...and limits allowed-tools" eval 'grep -q "^allowed-tools: ." $CMD'
check "it points at the real installer" has $CMD install.sh

print -r -- "nudge hook"
check "plugin/scripts/nudge is executable" test -x $NUDGE
json $ROOT/plugin/hooks/hooks.json hooks.SessionStart.0.hooks.0.command
check "the SessionStart hook runs it from the plugin root" eval '[[ $REPLY == *\${CLAUDE_PLUGIN_ROOT}/scripts/nudge* ]]'
check "with a 5 second timeout" json_is $ROOT/plugin/hooks/hooks.json hooks.SessionStart.0.hooks.0.timeout 5
check "it is not a second recording hook" eval '[[ "$(<$ROOT/plugin/hooks/hooks.json)" != *SessionEnd* ]]'

# A stand-in undead somewhere on PATH, reporting whichever version a case needs
mkdir -p $SANDBOX/installed
fake_undead() { print -l -- '#!/bin/sh' "echo \"undead $1\"" > $SANDBOX/installed/undead; chmod +x $SANDBOX/installed/undead }
json $P/plugin.json version; PLUGIN_VERSION=$REPLY
fake_undead $PLUGIN_VERSION
nudge() { out=$(env PATH=$1 CLAUDE_PLUGIN_ROOT=$ROOT/plugin $NUDGE </dev/null 2>&1); rc=$? }
one_line() { [[ $1 != *$'\n'* ]] }

nudge $SANDBOX/installed:/usr/bin:/bin
check "says nothing when the CLI is as new as the plugin" test -z "$out"
check "...and exits 0" test $rc -eq 0
check "...and leaves no stamp behind" missing $STAMP

check "the plugin ships no bin/, so nothing shadows undead on Claude's PATH" test ! -e $ROOT/plugin/bin

nudge /usr/bin:/bin
check "it speaks up when undead is missing" test -n "$out"
check "...and the message sends the user to /undead" eval '[[ $out == *"systemMessage"*"/undead"* ]]'
check "...on one line" one_line "$out"
check "...as JSON Claude Code can parse" eval 'print -r -- "$out" | plutil -extract systemMessage raw -o - - >/dev/null'
check "...exiting 0" test $rc -eq 0
check "...and stamps the state dir" test -f $STAMP

nudge /usr/bin:/bin
check "the second session within 24h says nothing" test -z "$out"
check "...and exits 0" test $rc -eq 0

touch -t $(strftime '%Y%m%d%H%M' $(( EPOCHSECONDS - 90000 ))) $STAMP
nudge /usr/bin:/bin
check "a day later it says it again" test -n "$out"

mkdir -p $HOME/.local/bin
cp $SANDBOX/installed/undead $HOME/.local/bin/undead
zf_rm -f $STAMP
nudge /usr/bin:/bin
check "~/.local/bin/undead counts even when PATH misses it" test -z "$out"
check "...and exits 0" test $rc -eq 0

# The plugin travels with a version of undead; when it is ahead of the CLI, say so instead of staying quiet
print -r -- "a newer undead"
zf_rm -f $HOME/.local/bin/undead
fake_undead 0.0.1
nudge $SANDBOX/installed:/usr/bin:/bin
check "an older CLI is told a newer one exists" eval '[[ $out == *"undead $PLUGIN_VERSION is available (you have 0.0.1)"* ]]'
check "...and which command updates it" eval '[[ $out == *"undead upgrade"* ]]'
check "...on one line of JSON" eval 'one_line "$out" && print -r -- "$out" | plutil -extract systemMessage raw -o - - >/dev/null'
check "...exiting 0" test $rc -eq 0
check "...stamped for this version" test -f ${STAMP:h}/upgrade-$PLUGIN_VERSION

nudge $SANDBOX/installed:/usr/bin:/bin
check "the second session that day says nothing" test -z "$out"

fake_undead 99.0.0
nudge $SANDBOX/installed:/usr/bin:/bin
check "a CLI newer than the plugin is left alone" test -z "$out"

finish
