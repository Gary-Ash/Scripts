### Gary's Utility Scripts

A collection of utility scripts and shell libraries for macOS development, system maintenance, and workflow automation.

## Table of Contents

- [Scripts](#scripts)
- [Shell Library Functions](#shell-library-functions)

---

## Scripts

| Script | Language | Description |
|--------|----------|-------------|
| [blog-post.sh](#blog-postsh) | Bash | Create Jekyll blog posts |
| [bootstrap.sh](#bootstrapsh) | Bash | Bootstrap a new Mac setup |
| [check-path.pl](#check-pathpl) | Perl | Validate PATH directories |
| [find-permission-based-API-usage.sh](#find-permission-based-api-usagesh) | Bash | Find iOS permission-requiring APIs |
| [fix-xcode-templates.pl](#fix-xcode-templatespl) | Perl | Fix Xcode file header templates |
| [format-project.sh](#format-projectsh) | Bash | Format source code in projects |
| [git-rebase-mine-to.sh](#git-rebase-mine-tosh) | Bash | Git merge and rebase utility |
| [load-simulator.pl](#load-simulatorpl) | Perl | Restore iOS simulator state |
| [meeting-direct-link.py](#meeting-direct-linkpy) | Python | Convert meeting URLs to app links |
| [new-xcode-project.pl](#new-xcode-projectpl) | Perl | Generate Xcode projects from templates |
| [ocd.sh](#ocdsh) | Bash | System cleanup and maintenance |
| [refresh-compile-commands.sh](#refresh-compile-commandssh) | Bash | Regenerate LSP compile_commands.json |
| [refresh-safari-icons.sh](#refresh-safari-iconssh) | Bash | Restore custom Safari favicons |
| [reset-dates.pl](#reset-datespl) | Perl | Reset file dates and copyright headers |
| [settings.sh](#settingssh) | Bash | Configure macOS system settings |
| [startup-banner.pl](#startup-bannerpl) | Perl | Display terminal startup banner |
| [strip-comments.pl](#strip-commentspl) | Perl | Remove comments from C-style source |
| [sync-mac.sh](#sync-macsh) | Bash | Sync files between Mac systems |
| [update-dots.sh](#update-dotssh) | Bash | Maintain dotfiles repository |
| [update-site.sh](#update-sitesh) | Bash | Deploy Jekyll website |
| [wtf-autolayout.py](#wtf-autolayoutpy) | Python | Debug Auto Layout constraints |

---

## Script Details

### blog-post.sh

Creates a new Jekyll blog post or product page with the appropriate front matter and timestamp. Generates files in the `~/Sites/geedbla.com/` directory structure.

**Usage:** `blog-post.sh <blog|products> "Title"`

---

### bootstrap.sh

Bootstraps a fresh macOS installation by setting up dotfiles, installing Homebrew packages, configuring shells (bash/zsh), installing Ruby gems and Python packages, and setting up the ZDOTDIR environment.

---

### check-path.pl

Scans the current PATH environment variable and reports which directories exist and which are missing. Outputs a clean PATH declaration containing only valid directories.

**Usage:** `check-path.pl`

---

### find-permission-based-API-usage.sh

Scans Swift and Objective-C source files for usage of APIs that require runtime permissions or entitlements (e.g., file dates, system uptime, disk capacity, UserDefaults).

**Usage:** `find-permission-based-API-usage.sh <directory>`

---

### fix-xcode-templates.pl

Modifies Xcode's internal file and project templates to remove the `//` comment prefix from `___FILEHEADER___` placeholders, allowing custom file headers to work correctly.

**Note:** Requires sudo privileges.

---

### format-project.sh

Runs multiple code formatters on a project directory including uncrustify (C/Objective-C), swiftformat (Swift), black (Python), shfmt (Bash), and perltidy (Perl).

**Usage:** `format-project.sh [directory]`

---

### git-rebase-mine-to.sh

Merges the current branch into a target branch (with --no-ff) and then rebases the current branch onto the target branch.

**Usage:** `git-rebase-mine-to.sh <branch>`

---

### load-simulator.pl

Resets all iOS simulators and restores a consistent state by loading media files from a backup folder into each simulator.

---

### meeting-direct-link.py

Converts Microsoft Teams and Zoom web URLs into direct app launch URLs (msteams:// and zoommtg:// protocols).

**Usage:** `meeting-direct-link.py <url>`

---

### new-xcode-project.pl

Generates a new Xcode project from customizable templates. Supports options for GitHub repository creation, open/closed source licensing, and in-file license headers.

**Usage:** `new-xcode-project.pl <template> <name> <location> [company] [bundle-id]`

**Options:**
- `-ng, --no-github` - Don't create GitHub repository
- `-nx, --no-xcode` - Don't open Xcode after generation
- `-cs, --closed` - Use closed source license
- `-lif, --inFileLicense` - Add license text to source files

---

### ocd.sh

Comprehensive macOS system maintenance script that updates Homebrew, gems, pip, and npm packages; cleans caches, history, and temporary files; resets application preferences; clears browser data; and performs various system optimizations.

**Usage:** `ocd.sh [restart|off]`

---

### refresh-compile-commands.sh

Regenerates `compile_commands.json` files for all Xcode projects in ~/Developer to enable LSP support in editors.

---

### refresh-safari-icons.sh

Downloads and installs custom Safari favicon files from a remote server to replace the default Apple icons.

---

### reset-dates.pl

Resets file creation/modification dates and updates copyright headers in source files. Handles various file types including Xcode project files and compiled AppleScript.

**Usage:** `reset-dates.pl "Company Name" [files|directories...]`

---

### settings.sh

Configures various macOS system defaults including Finder settings, keyboard behavior, Safari options, and Xcode preferences. Also enables developer tools security.

---

### startup-banner.pl

Displays a colorful terminal startup banner with system information including OS version, hardware specs, Homebrew status, IP addresses, disk usage, and battery status. Supports both light and dark themes.

**Usage:** `startup-banner.pl [--light|--dark]`

---

### strip-comments.pl

Removes all C-style comments (both `//` and `/* */`) from source files in a directory tree. Handles nested comments and preserves strings.

**Usage:** `strip-comments.pl [directory]`

---

### sync-mac.sh

Synchronizes directories, files, and package manager installations (Homebrew, pip, gems, npm) between multiple Mac systems over SSH.

---

### update-dots.sh

Maintains a dotfiles Git repository by collecting configuration files, preferences, and application settings from the system and pushing updates to GitHub.

**Usage:** `update-dots.sh [--package]`

---

### update-site.sh

Builds a Jekyll website and deploys it to a remote server via rsync.

---

### wtf-autolayout.py

Parses Auto Layout constraint warnings from Xcode and opens wtfautolayout.com with the constraint log for analysis and debugging help.

**Usage:** `wtf-autolayout.py <constraint-log>`

---

## Shell Library Functions

Reusable shell functions located in `lib/shell/lib/` that can be sourced into scripts.

### get_sudo_password.sh

Provides secure sudo password retrieval for scripts that require elevated privileges.

**Function:** `get_sudo_password`

**Description:** Retrieves the user's sudo password through a secure multi-step process:
1. First checks if sudo is already authenticated (non-interactive validation)
2. Attempts to retrieve the password from the macOS Keychain (`security find-generic-password`)
3. Falls back to interactive password prompt if keychain lookup fails

**Returns:** The sudo password on stdout (for use with `sudo --stdin`)

**Usage:**
```bash
source "/opt/geedbla/lib/shell/lib/get_sudo_password.sh"

SUDO_PASSWORD="$(get_sudo_password)"
echo "$SUDO_PASSWORD" | sudo --validate --stdin
```

---

### get_notary_password.sh

Provides secure retrieval of Apple notarization service credentials.

**Function:** `get_notary_password`

**Description:** Retrieves the Apple notarization service password for code signing workflows:
1. Attempts to retrieve the password from the macOS Keychain (`security find-generic-password`)
2. Falls back to interactive password prompt if keychain lookup fails

**Returns:** The notarization password on stdout

**Usage:**
```bash
source "/opt/geedbla/lib/shell/lib/get_notary_password.sh"

NOTARY_PASSWORD="$(get_notary_password)"
xcrun notarytool submit app.zip --apple-id "$APPLE_ID" --password "$NOTARY_PASSWORD"
```

---

## Author

Gary Ash <gary.ash@icloud.com>

## License

Copyright 2026 By Gary Ash. All rights reserved.
