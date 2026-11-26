#!/bin/bash
# Issue #150: with symbolic icons on, the toolbar and side pane use the XApp icon (xsi-<name>-symbolic)
# when the icon theme has it, fall back to <name>-symbolic when it doesn't, and the file view keeps its colour icons.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
TOOLBAR=150x100+0+0
SIDEPANE=165x600+0+90
FILEVIEW=780x480+200+120

ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/48x48"
mkdir -p "$ICONS/actions" "$ICONS/places"
for icon in actions/xsi-go-home-symbolic places/xsi-folder-symbolic; do
  convert -size 48x48 xc:'#bebebe' "$ICONS/$icon.png"
done

mkdir -p "$HOME/Projects" "$HOME/Notes" "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
echo "file://$HOME/Projects Projects" > "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"

xfconf-query -c thunar -p /misc-symbolic-icons-in-sidepane -n -t bool -s true
xfconf-query -c thunar -p /misc-symbolic-icons-in-toolbar -n -t bool -s true
xfconf-query -c thunar -p /misc-xapp-icons -n -t bool -s false
xfconf-query -c thunar -p /last-separator-position -n -t int -s 170
xfconf-query -c thunar -p /default-view -n -t string -s ThunarIconView

set_xapp() {  # true|false
  xfconf-query -c thunar -p /misc-xapp-icons -s "$1"
  sleep 1.5
}

region() {  # shot region
  convert "$SHOTS/$1.png" -crop "$2" +repage "$WORK/$1-$2.png"
  echo "$WORK/$1-$2.png"
}

differs() {  # shot-a shot-b region
  local ae
  ae=$(compare -metric AE "$(region "$1" "$3")" "$(region "$2" "$3")" null: 2>&1) || true
  [[ $ae =~ ^[0-9.e+]+$ ]] || fail "could not compare $1 and $2 in $3: $ae"
  [[ $ae != 0 ]]
}

changed_icons() {  # shot-a shot-b: how many side-pane icons differ
  compare "$(region "$1" "$SIDEPANE")" "$(region "$2" "$SIDEPANE")" -compose src -highlight-color white -lowlight-color black \
    "$WORK/diff-$1-$2.png" 2>/dev/null || true
  convert "$WORK/diff-$1-$2.png" -threshold 50% -morphology Dilate Square:4 \
    -define connected-components:verbose=true -connected-components 8 null: | grep -c 'gray(255)' || true
}

expect_icons() {  # shot-a shot-b count message
  local n
  n=$(changed_icons "$1" "$2")
  [[ $n == "$3" ]] || fail "$4 ($n side-pane icons differ between $1 and $2, expected $3)"
}

open_thunar "$HOME"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" home
focus "$MAIN"
xdotool mousemove --window "$MAIN" $((W - 20)) $((H - 10))
sleep 1

shot "$MAIN" before-xapp "misc-xapp-icons off: the toolbar Home button, the Home place and the Projects bookmark show the theme's symbolic icons"
set_xapp true
shot "$MAIN" after-xapp "misc-xapp-icons on: the toolbar Home button, the Home place and the Projects bookmark show the solid-square xsi-* fixtures; Projects and Notes in the file view keep colour folder icons"
pair xapp "Turned the hidden preference misc-xapp-icons on" \
  "Symbolic icons in the toolbar and side pane come from xsi-*-symbolic when installed" \
  "theme's symbolic icons" "xsi-* fixtures: solid squares"

differs before-xapp after-xapp "$TOOLBAR" || fail "the toolbar's Home button did not change when misc-xapp-icons was turned on"
expect_icons before-xapp after-xapp 2 "turning misc-xapp-icons on did not change exactly the Home place and the Projects bookmark"
! differs before-xapp after-xapp "$FILEVIEW" || fail "the file view's icons changed with misc-xapp-icons; they must stay colour icons"

rm "$ICONS/actions/xsi-go-home-symbolic.png"
touch "$ICONS/.." "$ICONS/../.."
sleep 6
set_xapp false
set_xapp true
shot "$MAIN" fallback-home "xsi-go-home-symbolic removed: the toolbar Home button and the Home place fall back to the theme's go-home-symbolic, while the Projects bookmark keeps its solid-square xsi-folder-symbolic"

! differs before-xapp fallback-home "$TOOLBAR" || fail "without xsi-go-home-symbolic the toolbar's Home button did not fall back to go-home-symbolic"
expect_icons after-xapp fallback-home 1 "removing xsi-go-home-symbolic did not change only the Home place"
expect_icons before-xapp fallback-home 1 "without xsi-go-home-symbolic the side pane is not back to the theme's Home icon with Projects still on xsi-folder-symbolic"
