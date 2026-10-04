# Dev Decrufter for Mac

A small, local-first macOS cleanup utility for developer machines. It provides a browser interface and a Bash CLI for previewing and running targeted cleanup tasks such as Xcode build data, Simulator caches, package-manager caches, and old Android Studio support folders.

The tool is deliberately phase-based: inspect one category at a time before removing anything.

> [!WARNING]
> Cleanup operations permanently delete local caches, build artifacts, and other generated data. Start with a dry run, review the target, and close affected development tools first. The Spotlight phase uses `sudo`, resets the disk index, and can make search results temporarily unavailable while macOS rebuilds it.

## Requirements

- macOS
- Bash (included with macOS)
- Node.js 18 or later for the local web interface

Some phases also rely on tools that are only needed when you use that phase:

- Homebrew for `homebrew`
- Xcode Command Line Tools / Xcode for `unavailable-simulators`

There are no npm packages to install.

## Quick start

Clone the repository, then launch the local interface:

```bash
git clone https://github.com/<your-github-username>/dev-decrufter-for-mac.git
cd dev-decrufter-for-mac
./run.sh
```

Open <http://127.0.0.1:4173>. The server listens only on the local machine. Select **Preview** first; choose **Clean now** only after reviewing the result and confirming the prompt.

To use another local port:

```bash
PORT=8080 ./run.sh
```

Press `Ctrl+C` to stop the server.

## Command-line usage

`cleanup.sh` runs all cleanup phases by default. Use `--dry-run` to see the available targets and size estimates without deleting anything.

```bash
# Preview every phase
./cleanup.sh --dry-run

# Preview one phase
./cleanup.sh --phase=xcode-derived-data --dry-run

# Run one phase
./cleanup.sh --phase=gradle-caches

# Run all phases except Homebrew and Spotlight
./cleanup.sh --skip-brew --skip-spotlight
```

Available options:

| Option | Description |
| --- | --- |
| `--dry-run` | Print planned work and estimates without deleting files. |
| `--phase=<name>` | Run or preview one cleanup phase. |
| `--skip-brew` | Omit the Homebrew cleanup when running all phases. |
| `--skip-spotlight` | Omit the Spotlight reset when running all phases. |

## Cleanup phases

| Phase name | What it affects |
| --- | --- |
| `homebrew` | Old Homebrew downloads and unused formula versions via `brew cleanup`. |
| `xcode-derived-data` | `~/Library/Developer/Xcode/DerivedData/*` build products and indexes. |
| `xcode-derived-data-workaround` | `~/Library/Developer/Xcode/DerivedDataWorkaround/*`. |
| `xcode-archives` | `~/Library/Developer/Xcode/Archives/*` local archives. |
| `unavailable-simulators` | Unavailable iOS Simulator device records via `xcrun simctl delete unavailable`. |
| `core-simulator-caches` | `~/Library/Developer/CoreSimulator/Caches`. |
| `cocoapods-cache` | `~/Library/Caches/CocoaPods`. |
| `npm-cache` | `~/.npm`. |
| `yarn-cache` | `~/.yarn/cache`. |
| `macos-app-caches` | Everything in `~/Library/Caches/*`. Use extra care: apps recreate these files, but first launch may be slower. |
| `spotlight` | Turns Spotlight off, removes its data-volume index, then enables and rebuilds it. Requires administrator authentication. |
| `gradle-caches` | `~/.gradle/caches`. Dependencies will be downloaded again. |
| `gradle-daemon` | `~/.gradle/daemon`. |
| `android-studio` | Older `~/Library/Application Support/Google/AndroidStudio*` folders; keeps the newest folder by reverse alphabetical name. |

## Safety notes

- The web UI accepts only the predefined phases and binds to `127.0.0.1`; it is not intended to be exposed to a network.
- Previews are advisory. Files can change between a preview and the actual cleanup.
- The script continues after individual command failures so it can report the rest of the cleanup. Read the output after each run.
- Close Xcode, Android Studio, and other affected tools before deleting their caches or generated artifacts.
- Project source code is not a direct target, but deleting build artifacts or caches can require a rebuild or dependency download.

## Project layout

| File | Purpose |
| --- | --- |
| `cleanup.sh` | Cleanup implementation and CLI. |
| `server.js` | Dependency-free local HTTP server and API. |
| `index.html` | Single-page local web interface. |
| `run.sh` | Convenience launcher for the web interface. |
| `cleanup-history.json` | Local UI history, created at runtime and intentionally ignored by Git. |
