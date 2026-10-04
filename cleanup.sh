#!/bin/bash

set -uo pipefail

DRY_RUN=false
SKIP_BREW=false
SKIP_SPOTLIGHT=false
PHASE=""
TOTAL_BYTES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --skip-brew)
      SKIP_BREW=true
      ;;
    --skip-spotlight)
      SKIP_SPOTLIGHT=true
      ;;
    --phase=*)
      PHASE="${arg#--phase=}"
      ;;
    --phase)
      echo "Use --phase=name"
      exit 1
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--dry-run] [--skip-brew] [--skip-spotlight] [--phase=name]"
      exit 1
      ;;
  esac
done

phase_is() {
  [[ -z "$PHASE" || "$PHASE" == "$1" ]]
}

log() {
  echo ""
  echo "==> $1"
}

print_mode() {
  echo "    Mode: $([ "$DRY_RUN" = true ] && echo "dry run" || echo "execute")"
  echo "    Skip Homebrew: $SKIP_BREW"
  echo "    Skip Spotlight: $SKIP_SPOTLIGHT"
}

bytes_to_human() {
  local bytes="${1:-0}"
  awk -v sum="$bytes" '
    function human(x) {
      s="B KB MB GB TB PB"
      split(s, units, " ")
      i=1
      while (x >= 1024 && i < 6) {
        x /= 1024
        i++
      }
      if (i == 1) {
        return sprintf("%d%s", x, units[i])
      } else {
        return sprintf("%.1f%s", x, units[i])
      }
    }
    BEGIN { print human(sum) }
  '
}

add_bytes() {
  local n="${1:-0}"
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    TOTAL_BYTES=$((TOTAL_BYTES + n))
  fi
}

path_bytes() {
  local path="$1"
  if [[ -e "$path" ]]; then
    du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || true
  fi
}

sum_paths_bytes() {
  local total=0
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then
      local b
      b=$(du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}' || true)
      if [[ -n "${b:-}" && "$b" =~ ^[0-9]+$ ]]; then
        total=$((total + b))
      fi
    fi
  done
  echo "$total"
}

show_size() {
  local label="$1"
  local path="$2"
  local bytes=0

  if [[ -e "$path" ]]; then
    bytes=$(path_bytes "$path")
    if [[ -n "${bytes:-}" && "$bytes" =~ ^[0-9]+$ ]]; then
      echo "    Size: $(bytes_to_human "$bytes") - $label"
      add_bytes "$bytes"
    else
      echo "    Size: unknown - $label"
    fi
  else
    echo "    Size: 0B - $label (not found)"
  fi
}

show_glob_size() {
  local label="$1"
  shift
  local paths=()
  local p

  for p in "$@"; do
    [[ -e "$p" ]] && paths+=("$p")
  done

  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "    Size: 0B - $label (not found or empty)"
    return
  fi

  local bytes
  bytes=$(sum_paths_bytes "${paths[@]}")
  if [[ -n "${bytes:-}" && "$bytes" =~ ^[0-9]+$ ]]; then
    echo "    Size: $(bytes_to_human "$bytes") - $label"
    add_bytes "$bytes"
  else
    echo "    Size: unknown - $label"
  fi
}

run_cmd() {
  local description="$1"
  shift

  echo "    Command: $description"
  if [[ "$DRY_RUN" == true ]]; then
    echo "    Dry run: skipped"
  else
    "$@" || true
    echo "    Done"
  fi
}

preview_or_run_brew_cleanup() {
  log "Cleaning Homebrew"

  if [[ "$SKIP_BREW" == true ]]; then
    echo "    Skipped"
    return
  fi

  echo "    Homebrew auto-update: disabled for this run"

  if [[ "$DRY_RUN" == true ]]; then
    echo "    Preview: brew cleanup will remove old downloads and unused versions"
    HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n || true
  else
    HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup || true
    echo "    Done"
  fi
}

preview_or_run_simctl_cleanup() {
  log "Removing unavailable iOS simulators"
  if [[ "$DRY_RUN" == true ]]; then
    echo "    Preview: xcrun simctl delete unavailable"
    xcrun simctl list devices unavailable || true
  else
    xcrun simctl delete unavailable || true
    echo "    Done"
  fi
}

preview_or_run_spotlight_reset() {
  log "Resetting Spotlight index"

  if [[ "$SKIP_SPOTLIGHT" == true ]]; then
    echo "    Skipped"
    return
  fi

  local spotlight_path="/System/Volumes/Data/.Spotlight-V100"
  show_size "Spotlight index" "$spotlight_path"

  if [[ "$DRY_RUN" == true ]]; then
    echo "    Command: sudo mdutil -i off /"
    echo "    Dry run: skipped"
    echo "    Command: sudo killall mds || true"
    echo "    Dry run: skipped"
    echo "    Command: sudo killall mdworker || true"
    echo "    Dry run: skipped"
    echo "    Command: sudo rm -rf /System/Volumes/Data/.Spotlight-V100"
    echo "    Dry run: skipped"
    echo "    Command: sudo mdutil -i on /"
    echo "    Dry run: skipped"
    echo "    Command: sudo mdutil -E /"
    echo "    Dry run: skipped"
  else
    sudo mdutil -i off / || true
    sudo killall mds || true
    sudo killall mdworker || true
    sudo rm -rf /System/Volumes/Data/.Spotlight-V100 || true
    sudo mdutil -i on / || true
    sudo mdutil -E / || true
    echo "    Done"
  fi
}

preview_or_run_android_studio_cleanup() {
  log "Cleaning old Android Studio support folders"

  local base="$HOME/Library/Application Support/Google"
  local folders=()
  local old_folders=()
  local line
  local total=0

  while IFS= read -r line; do
    folders+=("$line")
  done < <(find "$base" -maxdepth 1 -type d -name 'AndroidStudio*' -print 2>/dev/null | sort -r)

  if [[ ${#folders[@]} -eq 0 ]]; then
    echo "    No Android Studio folders found"
    return
  fi

  echo "    Installed folders:"
  printf '      %s\n' "${folders[@]}"

  if [[ ${#folders[@]} -gt 1 ]]; then
    old_folders=("${folders[@]:1}")
  fi

  echo "    Folders to delete:"
  if [[ ${#old_folders[@]} -eq 0 ]]; then
    echo "      None"
    echo "    Size: 0B - old Android Studio folders"
  else
    printf '      %s\n' "${old_folders[@]}"
    total=$(sum_paths_bytes "${old_folders[@]}")
    if [[ -n "${total:-}" && "$total" =~ ^[0-9]+$ ]]; then
      echo "    Size: $(bytes_to_human "$total") - old Android Studio folders"
      add_bytes "$total"
    else
      echo "    Size: unknown - old Android Studio folders"
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "    Dry run: skipped"
  else
    if [[ ${#old_folders[@]} -gt 0 ]]; then
      rm -rf "${old_folders[@]}"
      echo "    Done"
    else
      echo "    Nothing to delete"
    fi
  fi
}

log "Starting cleanup"
print_mode

if phase_is "homebrew"; then
  preview_or_run_brew_cleanup
fi

if phase_is "xcode-derived-data"; then
log "Removing Xcode DerivedData"
show_glob_size "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData/"*
run_cmd "rm -rf ~/Library/Developer/Xcode/DerivedData/*" rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"*
fi

if phase_is "xcode-derived-data-workaround"; then
log "Removing Xcode DerivedDataWorkaround"
show_glob_size "Xcode DerivedDataWorkaround" "$HOME/Library/Developer/Xcode/DerivedDataWorkaround/"*
run_cmd "rm -rf ~/Library/Developer/Xcode/DerivedDataWorkaround/*" rm -rf "$HOME/Library/Developer/Xcode/DerivedDataWorkaround/"*
fi

if phase_is "xcode-archives"; then
log "Removing Xcode Archives"
show_glob_size "Xcode Archives" "$HOME/Library/Developer/Xcode/Archives/"*
run_cmd "rm -rf ~/Library/Developer/Xcode/Archives/*" rm -rf "$HOME/Library/Developer/Xcode/Archives/"*
fi

if phase_is "unavailable-simulators"; then
  preview_or_run_simctl_cleanup
fi

if phase_is "core-simulator-caches"; then
log "Clearing CoreSimulator caches"
show_size "CoreSimulator caches" "$HOME/Library/Developer/CoreSimulator/Caches"
run_cmd "rm -rf ~/Library/Developer/CoreSimulator/Caches" rm -rf "$HOME/Library/Developer/CoreSimulator/Caches"
fi

if phase_is "cocoapods-cache"; then
log "Removing CocoaPods cache"
show_size "CocoaPods cache" "$HOME/Library/Caches/CocoaPods"
run_cmd "rm -rf ~/Library/Caches/CocoaPods" rm -rf "$HOME/Library/Caches/CocoaPods"
fi

if phase_is "npm-cache"; then
log "Removing npm cache"
show_size "npm cache" "$HOME/.npm"
run_cmd "rm -rf ~/.npm" rm -rf "$HOME/.npm"
fi

if phase_is "yarn-cache"; then
log "Removing Yarn cache"
show_size "Yarn cache" "$HOME/.yarn/cache"
run_cmd "rm -rf ~/.yarn/cache" rm -rf "$HOME/.yarn/cache"
fi

if phase_is "macos-app-caches"; then
log "Removing general macOS application caches"
show_glob_size "macOS application caches" "$HOME/Library/Caches/"*
run_cmd "rm -rf ~/Library/Caches/*" rm -rf "$HOME/Library/Caches/"*
fi

if phase_is "spotlight"; then
  preview_or_run_spotlight_reset
fi

if phase_is "gradle-caches"; then
log "Removing Gradle caches"
show_size "Gradle caches" "$HOME/.gradle/caches"
run_cmd "rm -rf ~/.gradle/caches" rm -rf "$HOME/.gradle/caches"
fi

if phase_is "gradle-daemon"; then
log "Removing Gradle daemon data"
show_size "Gradle daemon data" "$HOME/.gradle/daemon"
run_cmd "rm -rf ~/.gradle/daemon" rm -rf "$HOME/.gradle/daemon"
fi

if phase_is "android-studio"; then
  preview_or_run_android_studio_cleanup
fi

log "Summary"
echo "    Estimated space to clear: $(bytes_to_human "$TOTAL_BYTES")"
echo "    Note: Homebrew and unavailable simulator cleanup are not included in this estimate."

log "Disk usage after cleanup"
if [[ "$DRY_RUN" == true ]]; then
  echo "    Dry run: skipped"
else
  df -h /
fi

log "Cleanup finished"
