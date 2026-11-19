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
