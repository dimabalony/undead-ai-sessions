# Homebrew formula for a personal tap. To publish:
#   1. Tag a release (git tag v0.1.0 && git push --tags)
#   2. shasum -a 256 of https://github.com/dimabalony/undead-ai-sessions/archive/refs/tags/v0.1.0.tar.gz
#   3. Put this file, with the sha256 filled in, in github.com/dimabalony/homebrew-tap as Formula/undead.rb
# Users then run: brew install dimabalony/tap/undead && undead install
class Undead < Formula
  desc "Brings Claude Code and Codex sessions back after quitting your terminal or rebooting"
  homepage "https://github.com/dimabalony/undead-ai-sessions"
  url "https://github.com/dimabalony/undead-ai-sessions/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_THE_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on :macos

  def install
    libexec.install "bin", "lib"
    bin.install_symlink libexec/"bin/undead"
  end

  def caveats
    <<~EOS
      Finish the setup (adds hooks to Claude Code and Codex, and one block to ~/.zshrc):
        undead install
      Then open a new terminal tab. Check everything with: undead doctor
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/undead version")
  end
end
