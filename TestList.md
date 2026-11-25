# Test List

- [x] a zsh script keeps `$+commands[bat]` intact after formatting
- ~~a bash script is still reformatted by shfmt~~ (dropped: verified by hand)
- ~~a shebang-less .sh script is still formatted as bash~~ (dropped: verified by hand)

## update-dots.sh: prune dot files removed from $HOME

- [x] a file deleted from a dot folder in $HOME is removed from the repo copy
- [x] a dot file deleted from $HOME is removed from the repo copy
- [x] a dot folder deleted from $HOME is removed from the repo copy
- [x] an ignored path already in the repo copy (e.g. .claude/skills) is kept
- [x] a dangling symlink in $HOME keeps its repo copy
- [x] a file deleted from the Xcode folder in $HOME is removed from the repo copy
- [ ] an excluded path in the Xcode repo copy (e.g. UserData/IB Support) is kept

## update-software.sh: update Ruby gems, pip packages, and npm globals

- [x] outdated gems are listed and `gem update` then `gem cleanup` run when confirmed
- [x] no gem update runs when `gem outdated` reports nothing
- [x] gem updates are skipped when gem is not installed
- ~~no gem update runs when the user declines~~ (dropped: confirm already guards the upgrade)
- [x] outdated pip packages are listed and upgraded with `pip3 install --upgrade <names>` when confirmed
- [x] no pip upgrade runs when `pip3 list --outdated` reports nothing
- [x] pip updates are skipped when pip3 is not installed
- ~~no pip upgrade runs when the user declines~~ (dropped: confirm already guards the upgrade)
- [x] outdated npm globals are listed and `npm update -g` runs when confirmed (`npm outdated -g` exits 1 when it finds any)
- [x] no npm update runs when `npm outdated -g` reports nothing
- [x] npm updates are skipped when npm is not installed
- ~~no npm update runs when the user declines~~ (dropped: confirm already guards the upgrade)
- [x] main runs the gem, pip, and npm updates

## get_sudo_password.sh: stop prompting at end of input

- [x] the prompt loop gives up with an empty password when stdin reaches EOF
- [x] a last line with no trailing newline is still tried as the password

## update-software.sh: --all approves every update

- [x] run with --all, outdated gems are updated with no answer on stdin
- [x] an unknown argument is reported and the script exits non-zero

## update-software.sh: update the macOS system Ruby gems too

- [x] outdated system gems are listed and `sudo /usr/bin/gem update` then `sudo /usr/bin/gem cleanup` run when confirmed
- [x] no system gem update runs when the system `gem outdated` reports nothing
- [x] system gem updates are skipped when the system gem is not installed
- [x] main runs the system gem update after the virtual environment gem update
- [x] with --all, system gems are updated without an answer on stdin

## update-software.sh: obtain sudo once and keep it alive for the whole run

- [x] start_sudo_keepalive validates sudo by feeding the get_sudo_password password to `sudo --validate --stdin`
- [x] start_sudo_keepalive starts a background loop that refreshes the timestamp with `sudo --non-interactive true`
- [x] cleanup stops the keep-alive loop
- [x] cleanup removes the Sparkle temp files under sudo without asking for the password again
- [x] update_cleanup repairs /Applications under sudo without asking for the password again
- [x] main obtains sudo before the first update runs
- [ ] start_sudo_keepalive warns when sudo rejects the password
- [x] a password beginning with -n or -e reaches sudo intact (echo swallows it)

## update-software.sh: system gems behind --system, RubyGems update for Homebrew Ruby

- [x] main skips the system gem update when run without --system
- [x] with --system, main runs the system gem update after the gem update
- [x] when confirmed, the Homebrew Ruby gem update runs `gem update --system` before `gem update`
- ~~with --system and --all, outdated system gems are updated without an answer on stdin~~ (dropped: covered by the --all system gem test and the --system main test)

## update-software.sh: only update system gems whose latest version suits the system Ruby

- [x] system_gem_compatible succeeds when the system Ruby satisfies the version's required Ruby version
- [x] system_gem_compatible fails when the version requires a newer Ruby than the system Ruby
- [x] system_gem_compatible fails when the version requires a newer RubyGems than the system's
- ~~system_gem_compatible fails when the version's details cannot be fetched~~ (dropped: already fails through pipefail and the JSON parse error)
- [x] system_gem_compatible treats a version with no ruby_version requirement as compatible
- ~~system_gem_compatible honors a compound requirement such as `>= 2.5, < 2.6`~~ (dropped: split(",") already handles it)
- ~~system_gem_compatible asks rubygems.org for the v2 details of the given gem version~~ (dropped: already requests that URL)
- [x] when confirmed, only the outdated system gems compatible with the system Ruby are passed to `sudo /usr/bin/gem update`
- [x] when no outdated system gem is compatible, no system gem update runs and none is listed

## safari-cleaner.py: keep the Microsoft sign-in cookies Copilot needs

- [x] a cookie on .login.microsoftonline.com is kept when the bookmark domains are just the whitelist
- [x] a cookie on copilot.com is kept when the bookmark domains are just the whitelist
- [ ] a cookie on a domain that is neither bookmarked nor whitelisted is dropped

## ocd-cleanup.py: remove junk plist keys through cfprefsd

- [x] a junk key at the top level of a plist is removed with `defaults delete`, and the other keys are kept
- ~~a plist with no junk keys gets no `defaults delete`~~ (dropped: defaults runs only inside the `if key in plist` check)
- [x] run as root under sudo, `defaults delete` runs as `$SUDO_USER`
- ~~a junk key nested under `values` is still removed~~ (dropped: unchanged code, and no plist on this Mac has a `values` dictionary)
- [x] a plist with a top-level junk key and a nested `values` junk key loses both
- ~~a junk key `defaults` fails to delete does not stop the run~~ (dropped: `check=False` already guards it)
- [x] podcastapp removes each `playState:` key with `defaults delete`
- [x] texturePacker removes each key containing `Users` with `defaults delete`
- [x] BBEdit removes its saved-bounds, gray-level, transform-panel, and checksum keys with `defaults delete`
- [x] books sets `BKRecentsLastCleared` with `defaults write -string`
- [x] xcode sets `IDETemplateOptions` with `defaults write -dict` and `NSNavLastRootDirectory` with `defaults write -string`
- [x] sublimeText sets `NSNavLastRootDirectory` with `defaults write -string`
- [x] sublimeMerge sets `NSNavLastRootDirectory` with `defaults write -string`
