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
