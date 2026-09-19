#!/usr/bin/env bash

# Remove what install.sh added: the marked blocks in your Hyprland and menu
# config, plus the scripts. Everything outside the markers is left alone.
#
#   ./uninstall.sh            keep ~/.config/omarchy/claude-projects
#   ./uninstall.sh --purge    remove it too

set -euo pipefail

tag="omarchy-claude-code"
purge=false
[[ ${1:-} == "--purge" ]] && purge=true

bin_dir="$HOME/.local/bin"
bindings="$HOME/.config/hypr/bindings.lua"
hyprland="$HOME/.config/hypr/hyprland.lua"
menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
projects_config="$HOME/.config/omarchy/claude-projects"

say() { printf '  %s\n' "$*"; }

# Drop the marked block, and the blank line that install.sh put in front of it.
drop_block() {
  local file=$1 begin=$2 end=$3 tmp
  [[ -f $file ]] || return 0
  grep -qxF -e "$begin" "$file" || return 0

  tmp=$(mktemp)
  awk -v b="$begin" -v e="$end" '
    $0 == b { s = 1; if (blank) blank = ""; next }
    $0 == e { s = 0; next }
    !s {
      if ($0 ~ /^[[:space:]]*$/) { blank = blank $0 "\n"; next }
      printf "%s", blank; blank = ""
      print
    }
    END { printf "%s", blank }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  say "cleaned  $file"
}

echo "Removing Claude Code launchers"

drop_block "$bindings" "-- >>> $tag" "-- <<< $tag"
drop_block "$hyprland" "-- >>> $tag" "-- <<< $tag"
drop_block "$menu" "  // >>> $tag" "  // <<< $tag"

for script in claude-in claude-pad claude-pick claude-projects-list claude-projects-sync; do
  [[ -f $bin_dir/$script ]] || continue
  rm -f "$bin_dir/$script"
  say "removed  $bin_dir/$script"
done

if [[ $purge == true && -f $projects_config ]]; then
  rm -f "$projects_config"
  say "removed  $projects_config"
elif [[ -f $projects_config ]]; then
  say "kept     $projects_config (--purge removes it)"
fi

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  say "hyprland reloaded"
fi

echo
echo "Done. SUPER + SHIFT + A is free again; Omarchy's own SUPER + SHIFT + CTRL + A still opens the agent."
