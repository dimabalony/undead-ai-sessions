source ${0:A:h}/helpers.zsh
source $ROOT/lib/common.zsh

# `undead upgrade` replaces bin/ and lib/ under the install directory with the latest release. curl is shadowed, so
# the suite never reaches GitHub: it serves a release tarball built from this checkout with a bumped version.
NEXT=99.0.0
INSTALL=$HOME/.local/share/undead
mkdir -p $SANDBOX/bin $SANDBOX/release $INSTALL

# A release tarball of this checkout, with the version bumped and a marker file so the swap is visible
build_release() {
  local stage=$SANDBOX/stage
  rm -rf $stage; mkdir -p $stage/undead-$NEXT
  cp -R $ROOT/bin $ROOT/lib $stage/undead-$NEXT/
  sed -i '' "s/^typeset -g UNDEAD_VERSION=.*/typeset -g UNDEAD_VERSION=$NEXT/" $stage/undead-$NEXT/lib/common.zsh
  print -r -- "from the release" > $stage/undead-$NEXT/lib/marker
  tar -czf $SANDBOX/release/undead.tar.gz -C $stage undead-$NEXT
}
build_release
print -r -- "{\"tag_name\":\"v$NEXT\"}" > $SANDBOX/release/latest.json

# curl: the release API and the tarball come from disk; anything else fails the way a dead network does
stub_curl() {  # stub_curl ok|fail
  print -l -- '#!/bin/sh' \
    "[ \"$1\" = fail ] && exit 7" \
    'for a in "$@"; do case "$a" in' \
    "  *releases/latest) cat $SANDBOX/release/latest.json; exit 0 ;;" \
    "  *.tar.gz) cat $SANDBOX/release/undead.tar.gz; exit 0 ;;" \
    'esac; done' \
    'exit 7' > $SANDBOX/bin/curl
  chmod +x $SANDBOX/bin/curl
}
stub_curl ok

# An install.sh-style layout: the CLI runs from ~/.local/share/undead/bin/undead
install_copy() {
  rm -rf $INSTALL/bin $INSTALL/lib
  cp -R $ROOT/bin $ROOT/lib $INSTALL/
  chmod +x $INSTALL/bin/undead $INSTALL/lib/hook
}
install_copy
U=$INSTALL/bin/undead
upgrade() { out=$(PATH=$SANDBOX/bin:$PATH $U upgrade "$@" 2>&1); rc=$? }

print -r -- "up to date"
sed -i '' "s/^typeset -g UNDEAD_VERSION=.*/typeset -g UNDEAD_VERSION=$NEXT/" $INSTALL/lib/common.zsh
upgrade
check "says so" eval '[[ $out == *"undead $NEXT is up to date"* ]]'
check "exits 0" test $rc -eq 0
check "changes nothing" missing $INSTALL/lib/marker

print -r -- "--check"
install_copy
upgrade --check
check "prints the installed version" eval '[[ $out == *"installed: $UNDEAD_VERSION"* ]]'
check "prints the latest version" eval '[[ $out == *"latest:    $NEXT"* ]]'
check "points at the command" eval '[[ $out == *"undead upgrade"* ]]'
check "changes nothing" missing $INSTALL/lib/marker
check "exits 0" test $rc -eq 0

print -r -- "upgrade"
upgrade
check "names both versions" eval '[[ $out == *"undead $UNDEAD_VERSION -> $NEXT"* ]]'
check "replaces lib/" has $INSTALL/lib/marker "from the release"
check "replaces bin/" eval '[[ "$($INSTALL/bin/undead version)" == "undead $NEXT" ]]'
check "leaves the CLI executable" test -x $INSTALL/bin/undead
check "leaves the hook executable" test -x $INSTALL/lib/hook
check "leaves no staging directories behind" eval '[[ -z "$($INSTALL/(bin|lib).(new|old)(N))" ]]'
check "reminds you to check it" eval '[[ $out == *"undead doctor"* ]]'
check "exits 0" test $rc -eq 0

print -r -- "no network"
install_copy
stub_curl fail
upgrade
check "says it couldn't reach GitHub" eval '[[ $out == *"could not reach GitHub"* ]]'
check "exits 1" test $rc -eq 1
check "changes nothing" missing $INSTALL/lib/marker
upgrade --check
check "--check fails the same way" test $rc -eq 1
stub_curl ok

print -r -- "Homebrew"
BREW=$SANDBOX/brew/opt/undead/libexec
mkdir -p $BREW
cp -R $ROOT/bin $ROOT/lib $BREW/
chmod +x $BREW/bin/undead
out=$(PATH=$SANDBOX/bin:$PATH $BREW/bin/undead upgrade 2>&1); rc=$?
check "sends you to brew" eval '[[ $out == *"brew upgrade undead"* ]]'
check "exits 0" test $rc -eq 0
check "downloads nothing" missing $BREW/lib/marker

finish
