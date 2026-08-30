#!/usr/bin/env bash
set -euo pipefail
#*****************************************************************************************
# bootstrap.sh
#
# This script bootstraps a new Mac — it installs the dot files, Homebrew, the
# /opt/geedbla script tree, the Prompt and startup-banner binaries, and the
# Ruby, Python, and npm packages
#
# Author   :  Gary Ash <gary.ash@icloud.com>
# Created  :   1-Sep-2026  4:42pm
# Modified :
#
# Copyright © 2026 By Gary Ash All rights reserved.
#*****************************************************************************************

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DOTFILES"

RUBY_VERSION="4.0.1"
PYTHON_VENV="/opt/venv/python3"
PYTHON_BIN="/opt/homebrew/opt/python@3.14/bin/python3.14"

setZDOTDIR() {
	cat <<'EOF' | sudo tee -a /etc/zshenv &>/dev/null
if [[ -d "$HOME/.config/zsh" ]]; then
	export ZDOTDIR="$HOME/.config/zsh"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_CACHE_HOME="$HOME/.cache"
	export GNUPGHOME="$XDG_CONFIG_HOME/.gnupg"
fi
EOF
	sudo chmod 444 /etc/zshenv
	sudo chown root:wheel /etc/zshenv
}

# These are release assets rather than something built here, and /releases/latest
# resolves to whatever the newest release is, so no version has to be pinned. A
# machine with no network still boots to a working shell, so a failure here warns
# instead of aborting the run. Each archive holds one bare binary named for the
# asset.
installRelease() {
	local repo="$1" name="$2" tmp
	tmp="$(mktemp -d)"

	if curl -fsSL -o "$tmp/$name.zip" \
		"https://github.com/$repo/releases/latest/download/$name.zip" &&
		unzip -qo "$tmp/$name.zip" -d "$tmp"; then
		if [[ ! -d /opt/bin ]]; then
			sudo mkdir -p /opt/bin
			sudo chown "$USER:wheel" /opt/bin
			sudo chmod 755 /opt/bin
		fi
		install -m 755 "$tmp/$name" "/opt/bin/$name"
	else
		echo "bootstrap: could not install the latest $name release, do it by hand" >&2
	fi

	rm -rf "$tmp"
}

# Shortcuts exposes no import verb, so the best we can do is raise the import
# sheet for anything not already in the library and let it be confirmed there
importShortcuts() {
	local installed file name

	[[ -d shortcuts ]] || return 0
	installed="$(shortcuts list 2>/dev/null || true)"

	for file in shortcuts/*.shortcut; do
		[[ -e $file ]] || continue

		name="$(basename "$file" .shortcut)"
		if grep -qxF "$name" <<<"$installed"; then
			continue
		fi

		# needs a GUI session, so never let a headless run die here
		if open -a Shortcuts "$file" 2>/dev/null; then
			echo "Shortcuts: confirm the import sheet for \"$name\""
		else
			echo "Shortcuts: could not open \"$name\", import it by hand" >&2
		fi
	done
}

# .gitkeep is what holds the empty directories in git, so exclude it from the
# copy rather than deleting it out of the working tree
RSYNC=(rsync -rl --exclude=.gitkeep --exclude=.DS_Store)

find . -path ./.git -prune -o -name ".DS_Store" -exec rm -f {} +

mkdir -p "$HOME/.cache/zsh"
find . -path ./.git -prune -o -type f -exec chmod 600 {} +
find . -path ./.git -prune -o -type d -exec chmod 755 {} +

# the blanket 600 above strips the execute bit from everything meant to run
find . -path ./.git -prune -o -type f \( -name "*.sh" -o -name "*.pl" \) -exec chmod 755 {} +
find "home/.config/git/template/hooks" -type f -exec chmod 755 {} +
find "BBEdit/Text Filters" -type f -exec chmod 755 {} +

mkdir -p "$HOME/Library/Script Libraries"
mkdir -p "$HOME/Library/Application Support/BBEdit"

# trailing slashes, not globs — every entry under home/ is a dotfile
"${RSYNC[@]}" "home/" "$HOME/"
"${RSYNC[@]}" "xcode/" "$HOME/Library/Developer/Xcode/"
"${RSYNC[@]}" "Script Libraries/" "$HOME/Library/Script Libraries/"
"${RSYNC[@]}" "BBEdit/" "$HOME/Library/Application Support/BBEdit/"

"${RSYNC[@]}" "preferences/" "$HOME/Library/Preferences/"
# cfprefsd caches these domains and would write its copy back over ours
killall cfprefsd 2>/dev/null || true

if ! command -v brew >/dev/null; then
	# the script body is an argument here, not piped, so stdin is still a TTY and
	# the installer would stop to ask for confirmation without this
	NONINTERACTIVE=1 /bin/bash -c \
		"$(curl -fsSL 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh')"

	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if ! brew --version >/dev/null 2>&1; then
	echo "bootstrap: Homebrew is not usable, install it by hand and re-run" >&2
	exit 1
fi

brew bundle --file="$DOTFILES/brew/Brewfile"

if ! brew bundle check --file="$DOTFILES/brew/Brewfile" >/dev/null 2>&1; then
	echo "bootstrap: some Brewfile entries did not install, run 'brew bundle check --verbose'" >&2
fi

# the scripts, shell libraries, and completions that .zshenv and .zprofile point
# at — /opt itself is root-owned, so the directory has to be made with sudo and
# handed over before git can write into it
if [[ ! -d /opt/geedbla/.git ]]; then
	sudo mkdir -p /opt/geedbla
	sudo chown "$USER:wheel" /opt/geedbla
	sudo chmod 755 /opt/geedbla
	git clone https://github.com/Gary-Ash/Scripts.git /opt/geedbla
fi

installRelease "Gary-Ash/Prompt" "Prompt"
installRelease "Gary-Ash/StartupBanner" "startup-banner"

SHELL_PATH="$(command -v bash)"
if ! grep -qxF "$SHELL_PATH" /etc/shells 2>/dev/null; then
	sudo sh -c "echo $SHELL_PATH >> /etc/shells"
fi

SHELL_PATH="$(command -v zsh)"
if ! grep -qxF "$SHELL_PATH" /etc/shells 2>/dev/null; then
	sudo sh -c "echo $SHELL_PATH >> /etc/shells"
fi
sudo chsh -s "$SHELL_PATH" "$USER"

# The rbenv root and the Python venv that .zshenv, .zprofile, and functions.zsh
# expect. These must exist before anything is installed into them — otherwise the
# gems land in the SIP-protected system Ruby and pip refuses to touch the
# Homebrew Python at all (PEP 668).
if [[ ! -d /opt/venv ]]; then
	sudo mkdir -p /opt/venv
	sudo chown root:wheel /opt/venv
	sudo chmod 700 /opt/venv
	sudo chmod +a \
		"$USER allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity" \
		/opt/venv
fi

export RBENV_ROOT="/opt/venv/ruby"
rbenv install --skip-existing "$RUBY_VERSION"
rbenv global "$RUBY_VERSION"
export PATH="$RBENV_ROOT/shims:$PATH"

if [[ ! -e "$PYTHON_VENV/pyvenv.cfg" ]]; then
	"$PYTHON_BIN" -m venv "$PYTHON_VENV"
fi
# shellcheck disable=SC1091
source "$PYTHON_VENV/bin/activate"

xargs gem install <"$DOTFILES/brew/gems.txt"
rbenv rehash

pip3 install --upgrade pip
pip3 install -r "$DOTFILES/brew/python-packages.txt"

# npm globals go to the Homebrew prefix that .zshenv points NODE_PATH at
export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/config"
xargs npm install -g <"$DOTFILES/brew/npm-packages.txt"

# gh takes one extension per invocation. They land under XDG_DATA_HOME, which is
# gh's own default but is also what .zshenv exports, so name it here rather than
# rely on the two agreeing. Re-installing one already present is a no-op.
if ! XDG_DATA_HOME="$HOME/.local/share" xargs -n1 gh extension install \
	<"$DOTFILES/brew/gh-extensions.txt"; then
	echo "bootstrap: some gh extensions did not install, check 'gh extension list'" >&2
fi

# compaudit is a zsh function, so it cannot run in this shell. zsh -f starts with
# a bare fpath, so seed it with what .zprofile adds — otherwise the completion
# directories that actually trigger the compinit warning are never audited.
insecure="$(zsh -fc '
	fpath=(
		/opt/homebrew/share/zsh-completions
		/opt/homebrew/share/zsh/site-functions
		/opt/geedbla/lib/shell/lib
		/opt/geedbla/zsh-completions
		$fpath
	)
	autoload -Uz compaudit
	compaudit' 2>/dev/null || true)"
if [[ -n $insecure ]]; then
	printf '%s\n' "$insecure" | xargs chmod g-w
fi

# the gem and pip installs run long enough to outlast the sudo timestamp
sudo -v

if [[ -e /etc/zshenv ]]; then
	if ! grep -Fq 'export ZDOTDIR' /etc/zshenv; then
		setZDOTDIR
	fi
else
	sudo touch /etc/zshenv
	setZDOTDIR
fi

importShortcuts
