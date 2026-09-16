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


# curl: everything comes from disk, and every call is logged so a test can prove which endpoint was used.
# It answers the three shapes bin/undead and install.sh use: `-I` on the release page (the redirect lookup, whose
# answer is the -w '%{url_effective}' string on stdout), the API (body, headers via -D, and the code from -w), and
# the tarball. Files under $SANDBOX/release decide what each one returns.
REL=$SANDBOX/release
cat > $SANDBOX/bin/curl <<SH
#!/bin/sh
printf '%s\n' "\$*" >> $REL/log
head= hdr= url=
want_hdr=0
for a in "\$@"; do
  if [ \$want_hdr = 1 ]; then hdr=\$a; want_hdr=0; continue; fi
  case "\$a" in
    -D) want_hdr=1 ;;
    -*I*) head=1 ;;
    https://*) url=\$a ;;
  esac
done
case "\$url" in
  *api.github.com*)
    code=\$(cat $REL/api_code 2>/dev/null || echo 200)
    [ "\$code" = 000 ] && { printf '\\n000'; exit 7; }
    [ -n "\$hdr" ] && cat $REL/api_headers > "\$hdr" 2>/dev/null
    cat $REL/api_body 2>/dev/null
    printf '\\n%s' "\$code"
    exit 0 ;;
  */releases/latest)
    [ -n "\$head" ] && [ -s $REL/redirect ] && { cat $REL/redirect; exit 0; }
    exit 7 ;;
  *.tar.gz)
    cat $REL/undead.tar.gz; exit 0 ;;
esac
exit 7
SH
chmod +x $SANDBOX/bin/curl

# redirect: the tag GitHub's release page redirects to, or nothing. api: 200 with a body, 000 for a dead network,
# or any other code with whatever body and headers the case needs.
redirect() { print -rn -- "$1" > $REL/redirect }
api() { print -r -- "${1:-200}" > $REL/api_code; print -rn -- "${2-}" > $REL/api_body; print -rn -- "${3-}" > $REL/api_headers }
requested() { [[ -s $REL/log && "$(<$REL/log)" == *$1* ]] }
forget_requests() { : > $REL/log }

TAGURL=https://github.com/dimabalony/undead-ai-sessions/releases/tag/v$NEXT
redirect $TAGURL
api 200 "{\"tag_name\":\"v$NEXT\"}"
forget_requests

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

print -r -- "finding the latest release"
install_copy
forget_requests
upgrade --check
check "the tag comes from the release page's redirect" eval '[[ $out == *"latest:    $NEXT"* ]]'
check "...so GitHub's rate-limited API is never called" eval '! requested api.github.com'

install_copy; forget_requests
redirect ''
upgrade
check "without the redirect it falls back to the API" has $INSTALL/lib/marker "from the release"
check "...and says so by asking for it" requested api.github.com

install_copy; forget_requests
redirect "https://github.com/dimabalony/undead-ai-sessions/releases/latest"
api 000
upgrade
check "a redirect that is not a tag is not mistaken for one" eval '[[ $out != *"latest"*"is up to date"* ]]'
check "...and the API decides instead" eval '[[ $out == *"could not reach GitHub"* ]]'
check "exits 1" test $rc -eq 1
check "changes nothing" missing $INSTALL/lib/marker

print -r -- "no network"
install_copy
redirect ''
api 000
upgrade
check "says it couldn't reach GitHub" eval '[[ $out == *"could not reach GitHub"* ]]'
check "exits 1" test $rc -eq 1
check "changes nothing" missing $INSTALL/lib/marker
upgrade --check
check "--check fails the same way" test $rc -eq 1

print -r -- "rate limited"
install_copy
redirect ''
RESET=$(( EPOCHSECONDS + 25 * 60 ))
api 403 '{"message":"API rate limit exceeded for 203.0.113.7."}' "x-ratelimit-remaining: 0
x-ratelimit-reset: $RESET"
upgrade
check "names the rate limit instead of blaming the network" eval '[[ $out == *"rate-limiting this network"* ]]'
check "...and says how long to wait" eval '[[ $out == *"try again in 25 minutes"* ]]'
check "exits 1" test $rc -eq 1
api 403 '{"message":"API rate limit exceeded for 203.0.113.7."}' 'x-ratelimit-remaining: 0'
upgrade
check "without a reset header it just says later" eval '[[ $out == *"try again later"* ]]'

print -r -- "other answers"
install_copy
api 503 'upstream is sad'
upgrade
check "an unexpected status is quoted, not guessed at" eval '[[ $out == *"GitHub answered HTTP 503"* ]]'
check "exits 1" test $rc -eq 1
api 200 '{"message":"not a release"}'
upgrade
check "a body with no tag is reported" eval '[[ $out == *"no release tag"* ]]'

redirect $TAGURL
api 200 "{\"tag_name\":\"v$NEXT\"}"

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
