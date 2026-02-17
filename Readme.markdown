### Gary's Utility Scripts

A collection of utility scripts and shell libraries for macOS development, system maintenance, and workflow automation.

## Table of Contents

- [Scripts](#scripts)
- [Shell Library Functions](#shell-library-functions)
- [Zsh Shell Completions](#zsh-shell-completions)
- [Xcode Project Templates](#xcode-project-templates)

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

**Templates:** Project templates are located in `templates/Xcode/`. See [Xcode Project Templates](#xcode-project-templates).

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

**Usage:** `reset-dates.pl "Company Name" [file|directory ...]`

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

Synchronizes directories, files, and package manager installations between multiple Mac systems over SSH. Syncs:

- **Directories** — `~/.claude`, `~/.config`, `~/Developer`, `~/Documents`, `/opt/bin`, `/opt/geedbla`, BBEdit support files
- **Files** — `~/.claude.json`
- **Mail** — Mail archive (`~/Library/Mail`) and Mail preferences
- **Package managers** — Homebrew formulae and casks, pip packages, Ruby gems, npm packages (installs missing, removes extras)
- **Custom apps** — Bespoke applications (CleanStart.app, XcodeGeDblA.app) installed to `/Applications` via sudo. Sudo password prompts are suppressed and sync failures produce descriptive error messages without aborting the remaining sync operations.

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

## Zsh Shell Completions

Tab completion definitions located in `zsh-completion/` that can be added to a `$fpath` directory for zsh.

| File | Command | Description |
|------|---------|-------------|
| `_jekyll` | `jekyll` | Tab completion for Jekyll subcommands and options |
| `_new-xcode-project` | `new-xcode-project.pl` | Tab completion for project templates (dynamically read from `templates/Xcode/`) and all command-line flags |
| `_ocd` | `ocd.sh` | Tab completion for `ocd.sh` providing the `restart` and `off` subcommands |

---

## Xcode Project Templates

Reusable Xcode project templates located in `templates/Xcode/`, used by `new-xcode-project.pl` to generate new projects.

### Project Templates

| Template | Description |
|----------|-------------|
| `2DGame` | Multiplatform SpriteKit-based game (iOS, macOS, tvOS) |
| `AppKitProject` | AppKit-based macOS application with unit and UI tests |
| `MultiPlatform` | SwiftUI multiplatform app (iOS + macOS) with unit and UI tests |
| `UIKitProject` | UIKit-based iOS application with unit and UI tests |

Each template directory contains a complete `.xcodeproj` and source tree that `new-xcode-project.pl` copies and customizes with the project name, company, bundle identifier, and license.

### Shared Files (`_Files/`)

Files in `templates/Xcode/_Files/` are applied to every generated project regardless of template:

| File / Directory | Description |
|------------------|-------------|
| `.github/` | GitHub community health files: `CODE_OF_CONDUCT`, `CONTRIBUTING`, `FUNDING.yml`, issue templates, PR template, and a CI workflow |
| `.swiftlint.yml` | Project SwiftLint configuration |
| `.xcodesamplecode.plist` | Marks the project as Xcode sample code |
| `Assets.xcassets.zip` | Pre-built asset catalog (app icon slots, accent color, etc.) |
| `BuildEnv/` | Build phase scripts: `increment-build-number.sh`, `stamp-beta-version.sh`, `restore-stamped-icon.sh`, `swiftlint-project.sh` |
| `IDETemplateMacros.plist` | Xcode file header template macros |
| `IDETemplateMacros-Open.plist` | Header macros variant for open-source projects |
| `IDETemplateMacros-Closed.plist` | Header macros variant for closed-source projects |
| `LICENSE-Open.markdown` | Open-source license text |
| `LICENSE-Closed.markdown` | Closed-source license text |
| `ci.sh` | Local CI runner script |
| `organizations.txt` | Known organization names for copyright substitution |

---

## Author

Gary Ash <gary.ash@icloud.com>

## License

Copyright 2026 By Gary Ash. All rights reserved.
