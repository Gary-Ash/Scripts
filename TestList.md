# Test List

- [x] a zsh script keeps `$+commands[bat]` intact after formatting
- ~~a bash script is still reformatted by shfmt~~ (dropped: verified by hand)
- ~~a shebang-less .sh script is still formatted as bash~~ (dropped: verified by hand)

## update-dots.sh: prune dot files removed from $HOME

- [x] a file deleted from a dot folder in $HOME is removed from the repo copy
- [ ] a dot file deleted from $HOME is removed from the repo copy
- [ ] a dot folder deleted from $HOME is removed from the repo copy
- [ ] an ignored path already in the repo copy (e.g. .claude/skills) is kept
