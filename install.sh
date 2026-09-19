#!/usr/bin/env bash

# Install the Claude Code launchers into an Omarchy system.
#
# Everything written into your own config files sits between markers, so running
# this again updates those blocks in place instead of stacking duplicates.
# uninstall.sh removes them and leaves the rest of your config untouched.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tag="omarchy-claude-code"

bin_dir="$HOME/.local/bin"
bindings="$HOME/.config/hypr/bindings.lua"
hyprland="$HOME/.config/hypr/hyprland.lua"
menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

say() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- checks ----------------------------------------------------------------

command -v omarchy-agent >/dev/null || die "omarchy-agent not found; this installer is for Omarchy."
for tool in fzf jq; do
  command -v "$tool" >/dev/null || die "$tool is required (omarchy pkg add $tool)"
done
[[ -f $bindings ]] || die "$bindings not found"
[[ -f $hyprland ]] || die "$hyprland not found"

# --- helpers ---------------------------------------------------------------

# Everything in $1 that is NOT inside our own markers, so a re-run does not read
# back its own output and think the user already had it.
outside_block() {
  local file=$1 begin=$2 end=$3
  awk -v b="$begin" -v e="$end" '
    $0 == b { s = 1; next }
    $0 == e { s = 0; next }
    !s { print }
  ' "$file"
}

# Replace the marked block in $1, or append it when the markers are absent.
write_block() {
  local file=$1 begin=$2 end=$3 body=$4 tmp
  tmp=$(mktemp)

  # Rebuilt with head/tail rather than awk: awk -v unescapes its value, which
  # would turn a Lua pattern like "^org\\.omarchy" into an invalid escape.
  if grep -qxF -e "$begin" "$file" && grep -qxF -e "$end" "$file"; then
    local first last
    first=$(grep -nxF -e "$begin" "$file" | head -1 | cut -d: -f1)
    last=$(grep -nxF -e "$end" "$file" | head -1 | cut -d: -f1)
    head -n "$first" "$file" >"$tmp"
    printf '%s' "$body" >>"$tmp"
    tail -n +"$last" "$file" >>"$tmp"
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    printf '\n%s\n%s%s\n' "$begin" "$body" "$end" >>"$file"
  fi
}

# The menu file is a JSONC object, so the block goes inside the braces rather
# than at the end of the file.
write_menu_block() {
  local begin=$1 end=$2 body=$3 tmp brace

  mkdir -p "$(dirname "$menu")"
  [[ -f $menu ]] || printf '{\n}\n' >"$menu"

  if grep -qxF -e "$begin" "$menu" && grep -qxF -e "$end" "$menu"; then
    write_block "$menu" "$begin" "$end" "$body"
    return
  fi

  brace=$(grep -n '^}' "$menu" | tail -1 | cut -d: -f1)
  [[ -n $brace ]] || die "could not find the closing brace in $menu"

  tmp=$(mktemp)
  head -n "$((brace - 1))" "$menu" >"$tmp"
  printf '\n%s\n%s%s\n' "$begin" "$body" "$end" >>"$tmp"
  tail -n +"$brace" "$menu" >>"$tmp"
  mv "$tmp" "$menu"
}

# --- scripts ---------------------------------------------------------------

echo "Installing Claude Code launchers"

mkdir -p "$bin_dir"
install -m 755 "$repo"/bin/* "$bin_dir/"
say "scripts  -> $bin_dir/{$(cd "$repo/bin" && printf '%s,' * | sed 's/,$//')}"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) say "warning: $bin_dir is not on your PATH" ;;
esac

# --- keybindings -----------------------------------------------------------

lua_begin="-- >>> $tag"
lua_end="-- <<< $tag"

# SUPER + SHIFT + A is ChatGPT's web app in a stock Omarchy install, so it has to
# be released first -- unless this config already released it somewhere else.
unbind=""
if ! outside_block "$bindings" "$lua_begin" "$lua_end" | grep -qF 'hl.unbind("SUPER + SHIFT + A")'; then
  unbind='hl.unbind("SUPER + SHIFT + A") -- was ChatGPT'$'\n'
fi

bindings_body="-- Claude Code launchers: https://github.com/furkaanasik/omarchy-claude-code
${unbind}o.bind(\"SUPER + SHIFT + A\", \"Claude Code\", \"omarchy-launch-or-focus org.omarchy.agent claude-in\")
o.bind(\"SUPER + ALT + A\", \"Claude Code (project)\", \"claude-pick\")
o.bind(\"SUPER + A\", \"Claude scratchpad\", \"claude-pad\")
"

write_block "$bindings" "$lua_begin" "$lua_end" "$bindings_body"
say "bindings -> $bindings"

# --- window rules ----------------------------------------------------------

read -r -d '' hyprland_body <<'LUA' || true
-- claude-pad parks its window on its own special workspace, so SUPER + A can
-- drop Claude Code over the current workspace without touching the layout.
o.window({ class = "^org\\.omarchy\\.claudepad$" }, { workspace = "special:claude silent" })

-- The project picker opens as a popup. Once a project is chosen, claude-pick
-- untiles this same window and runs the session in it, so the frame only lasts
-- while picking.
o.window({ class = "^org\\.omarchy\\.agent\\.pick$" }, {
  float = true,
  center = true,
  size = { 875, 600 },
})
LUA

write_block "$hyprland" "$lua_begin" "$lua_end" "$hyprland_body"$'\n'
say "rules    -> $hyprland"

# --- menu ------------------------------------------------------------------

read -r -d '' menu_body <<'JSONC' || true
  // Claude Code. The rows between the inner markers are generated by
  // claude-projects-sync; edit that script or the folder list, not them.
  "claude": {"icon":"󰛄","label":"Claude Code","aliases":["claude","agent","code"]},
  "claude.pad": {"icon":"󰔎","label":"Scratchpad","description":"Toggle the Claude window over the current workspace","action":"claude-pad"},
  "claude.rescan": {"icon":"","label":"Refresh projects","action":"claude-projects-sync"},
  // >>> claude-projects
  // <<< claude-projects
JSONC

write_menu_block "  // >>> $tag" "  // <<< $tag" "$menu_body"$'\n'
say "menu     -> $menu"

# --- finish ----------------------------------------------------------------

PATH="$bin_dir:$PATH" claude-projects-sync >/dev/null 2>&1 || true
say "folders  -> $HOME/.config/omarchy/claude-projects"

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null
  errors=$(hyprctl configerrors 2>/dev/null || true)
  [[ -z ${errors//[[:space:]]/} ]] || printf '\nhyprland reported:\n%s\n' "$errors"
  say "hyprland reloaded"
fi

cat <<'DONE'

Done.

  SUPER + A              Claude scratchpad
  SUPER + SHIFT + A      open Claude Code, or focus the open one
  SUPER + ALT + A        pick a project, open Claude Code in it

Edit the scanned folders from the picker (ctrl-e) or in
~/.config/omarchy/claude-projects.
DONE
