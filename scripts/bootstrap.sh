#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# bootstrap.sh
#
# Boot strap a new Mac setup
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   3-Feb-2026  8:19pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

setZDOTDIR() {
	cat <<'EOF' | sudo tee -a "$HOME/Downloads/etc/zshenv" &>/dev/null
if [[ -d "$HOME/.config/zsh" ]]; then
	export ZDOTDIR="$HOME/.config/zsh"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_CACHE_HOME="$HOME/.cache"
	export GNUPGHOME="$XDG_CONFIG_HOME/.gnupg"
fi
EOF
	sudo chmod 444 "$HOME/Downloads/etc/zshenv"
	sudo chown root:wheel "$HOME/Downloads/etc/zshenv"
}

find "$HOME/Downloads/dotfiles/" -name ".gitkeep" -delete
find "$HOME/Downloads/dotfiles/" -name ".DS_Store" -delete

mkdir -p "$HOME/.cache/zsh"
find . -type f -exec chmod 600 {} \;
find . -type d -exec chmod 755 {} \;
find geedbla -type f -not -name "*.md" -exec chmod 755 {} \;

rsync -rz -delete home/* "$HOME"
rsync -rz -delete "Sublime Text/Local/" "$HOME/Library/Application Support/Sublime Text/Local"
rsync -rz -delete "Sublime Text/Packages/" "$HOME/Library/Application Support/Sublime Text/Packages"
rsync -rz -delete "xcode/" "$HOME/Library/Developer/Xcode/"

rsync -rz preferences/* "$HOME/Library/Preferences"

if ! command -v brew >/dev/null; then
	curl -fsS 'https://raw.githubusercontent.com/Homebrew/install/master/install' | ruby
fi

pushd brew || exit 1
brew bundle

SHELL_PATH="$(command -v bash)"
if ! grep "$SHELL_PATH" /etc/shells >/dev/null 2>&1; then
	sudo sh -c "echo $SHELL_PATH >> /etc/shells"
fi

SHELL_PATH="$(command -v zsh)"
if ! grep "$SHELL_PATH" /etc/shells >/dev/null 2>&1; then
	sudo sh -c "echo $SHELL_PATH >> /etc/shells"
fi
sudo chsh -s "$SHELL_PATH" "$USER"

touch ~/Downloads/paths
sudo cp -f ~/Downloads/paths /etc
sudo chown root:wheel /etc/paths
sudo chmod 644 /etc/paths
rm -f ~/Downloads/paths

# shellcheck disable=SC2162
while read p; do
	gem install "$p"
done <"$HOME/Downloads/dotfiles/brew/gems.txt"

# shellcheck disable=SC2162
pip3 install --upgrade pip
while read -r p; do
	pip3 install "$p"
done <"$HOME/Downloads/dotfiles/brew/python-packages.txt"

compaudit | xargs chmod g-w
if [[ -e "$HOME/Downloads/etc/zshenv" ]]; then
	if ! grep -Fq 'export ZDOTDIR' "$HOME/Downloads/etc/zshenv"; then
		setZDOTDIR
	fi
else
	sudo touch "$HOME/Downloads/etc/zshenv"
	setZDOTDIR
fi
