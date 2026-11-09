#!/bin/bash
# Issue #15: F2 on one file opens a rename popover next to the file, sized to the filename, instead of a free-floating dialog.
set -euo pipefail
. .github/scripts/verify-lib.sh

ROW0=$((103 + (EUID == 0 ? 34 : 0)))
NAME_X=230
DIR="$WORK/files"
LONG="$WORK/long"
LONGER="$WORK/longer"
APPS="$WORK/apps"
LONG_NAME="the-quarterly-report-on-the-northern-region-sales-with-all-of-the-appendices-and-the-charts-final-version.txt"
LONGER_NAME="$(printf 'an-extremely-long-file-name-%.0s' 1 2 3 4 5 6 7)that-goes-on-and-on-until-it-is-wider-than-the-window.txt"

mkdir -p "$DIR" "$LONG" "$LONGER" "$APPS"
for i in $(seq -w 1 40); do echo "$i" > "$DIR/file-$i.txt"; done
echo long > "$LONG/$LONG_NAME"
echo longer > "$LONGER/$LONGER_NAME"
cat > "$APPS/launcher.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Launcher
Exec=true
EOF
echo dbus > "$APPS/notes.txt"
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

P='Rename popover in the details view'
O='Other views and callers'

no_dialog() {
  ! xdotool search --onlyvisible --name '^Rename ' >/dev/null 2>&1 || fail "$1 opened a separate rename dialog instead of the popover"
}

exists() {
  local i
  for ((i = 0; i < 25; i++)); do
    [[ -e $1 ]] && return 0
    sleep 0.2
  done
  fail "$2: $(basename "$1") does not exist; the folder holds: $(ls "$(dirname "$1")" | tr '\n' ' ')"
}

absent() {
  [[ ! -e $1 ]] || fail "$2: $(basename "$1") exists, the rename was not cancelled"
}

f2() {
  focus "$MAIN"
  xdotool key F2
  sleep 1
}

click_first_row() {
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
  sleep 0.3
  xdotool click 1
  sleep 0.5
}

go_to() {
  focus "$MAIN"
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  xdotool key Return
  wait_title "$MAIN" "$(basename "$1")"
  sleep 0.5
}

find_window() {
  local i w
  for ((i = 0; i < 50; i++)); do
    w=$(xdotool search --onlyvisible --name "$1" 2>/dev/null | head -1) || true
    [[ -n $w ]] && { echo "$w"; return 0; }
    sleep 0.2
  done
  return 1
}

transient_for_main() {
  local parent
  parent=$(xprop -id "$1" WM_TRANSIENT_FOR 2>/dev/null | grep -o '0x[0-9a-f]*' || true)
  [[ -n $parent ]] && (( parent == MAIN )) || fail "$2 is not transient for the Thunar window (WM_TRANSIENT_FOR: '${parent:-none}', Thunar: $(printf '0x%x' "$MAIN"))"
}

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" 1000 600
xdotool windowmove --sync "$MAIN" 0 0
wait_title "$MAIN" files

click_first_row
shot "$MAIN" before-popover-below "file-01.txt, the first row of the details view, is selected and no rename UI is open"
f2
no_dialog "F2 on file-01.txt"
shot "$MAIN" after-popover-below "F2 opened the rename popover just below file-01.txt's name, pointing at it, inside the Thunar window, with 'file-01' selected but not '.txt'"
pair popover-below "Selected file-01.txt in the first row and pressed F2" "A file near the top gets the popover just below its name" "file-01.txt selected" "popover below file-01.txt" "$P"
xdotool type --delay 20 renamed-01
xdotool key Return
exists "$DIR/renamed-01.txt" "typing renamed-01 and Enter in the popover"
absent "$DIR/file-01.txt" "after renaming file-01.txt"

xdotool key End
sleep 0.5
shot "$MAIN" before-popover-above "With no click after the rename, End selected file-40.txt, the last row, at the bottom of the scrolled details view: the keyboard focus went back to the file list"
f2
no_dialog "F2 on the last row"
shot "$MAIN" after-popover-above "F2 opened the rename popover just above file-40.txt, because it doesn't fit below the last row"
pair popover-above "Pressed End to select the last row, then F2" "A file near the bottom gets the popover just above its name" "file-40.txt selected" "popover above file-40.txt" "$P"
xdotool type --delay 20 renamed-40
xdotool key Return
exists "$DIR/renamed-40.txt" "End, F2, renamed-40 and Enter after the first rename"
absent "$DIR/file-40.txt" "End, F2, renamed-40 and Enter: the focus did not go back to the file list, so End did not select the last row"
exists "$DIR/renamed-01.txt" "End, F2, renamed-40 and Enter"

f2
xdotool type --delay 20 escaped
xdotool key Escape
sleep 0.5
absent "$DIR/escaped.txt" "Escape"
exists "$DIR/renamed-40.txt" "after Escape"

f2
xdotool type --delay 20 clicked
xdotool mousemove --window "$MAIN" 80 450
sleep 0.3
xdotool click 1
sleep 0.5
absent "$DIR/clicked.txt" "a click outside the popover"
exists "$DIR/renamed-40.txt" "after a click outside the popover"
shot "$MAIN" click-outside "After typing 'clicked' in the popover, a click on the side pane closed it without renaming: renamed-40.txt is unchanged"

f2
xdotool type --delay 20 'bad/name'
sleep 0.5
xdotool key Return
sleep 0.5
absent "$DIR/bad" "Enter on an invalid name"
exists "$DIR/renamed-40.txt" "Enter on an invalid name"
shot "$MAIN" invalid-name "The popover with 'bad/name.txt' typed shows the invalid-name message and a greyed-out Rename, and Enter left it open without renaming"
xdotool key Escape
sleep 0.5

focus "$MAIN"
xdotool key Home
sleep 0.5
xdotool mousemove --window "$MAIN" 995 160
sleep 0.5
xdotool mousedown 1
for y in 161 162 163 164; do
  xdotool mousemove --window "$MAIN" 995 "$y"
  sleep 0.1
done
xdotool mouseup 1
xdotool mousemove --window "$MAIN" 500 400
sleep 0.8
shot "$MAIN" before-scroll-into-view "Home selected renamed-01.txt, the first row, and a drag on the scroll bar moved the view by part of a row, so the row is partly out of view at the top"
f2
shot "$MAIN" after-scroll-into-view "F2 scrolled renamed-01.txt fully into view and the popover points at it, just below its name"
pair scroll-into-view "Selected the first row with Home, dragged the scroll bar a few pixels, pressed F2" "F2 on a row partly out of view scrolls it in first, and the popover points at it" "first row partly out of view" "row scrolled in, popover points at it" "$P"
xdotool key Escape
sleep 0.5
xdotool mousemove --window "$MAIN" 500 400
for i in 1 2 3 4 5 6; do
  xdotool click 5
  sleep 0.1
done
sleep 0.8
shot "$MAIN" before-far-out-of-view "The mouse wheel scrolled the view down until the selected renamed-01.txt is far out of view above it"
f2
shot "$MAIN" after-far-out-of-view "F2 scrolled renamed-01.txt back to the top and the popover points at it, just below its name"
pair far-out-of-view "Scrolled the selected first row far out of view with the mouse wheel, pressed F2" "F2 on a row far out of view scrolls it back in, and the popover points at it" "selected row far out of view" "row scrolled in, popover points at it" "$P"
xdotool key Escape
sleep 0.5

xdotool windowsize --sync "$MAIN" 1280 700
go_to "$LONG"
click_first_row
f2
shot "$MAIN" long-name-full "In a 1280 px window the popover is wide enough to show the whole ${#LONG_NAME}-character name, with the name selected but not '.txt'"
xdotool key Escape
sleep 0.5

go_to "$LONGER"
click_first_row
f2
shot "$MAIN" long-name-capped "The ${#LONGER_NAME}-character name is wider than the window: the popover stops at 90% of the 1280 px window and the name scrolls inside the entry"
xdotool key Escape
sleep 0.5

focus "$MAIN"
xdotool key ctrl+1
sleep 1
xdotool key ctrl+a
f2
no_dialog "F2 in the icon view"
shot "$MAIN" icon-view-centered "In the icon view, F2 opens the popover pointing at the center of the view, inside the Thunar window"
xdotool key Escape
sleep 0.5
xdotool key ctrl+3
sleep 1
xdotool key ctrl+a
f2
no_dialog "F2 in the compact view"
shot "$MAIN" compact-view-centered "In the compact view, F2 opens the popover pointing at the center of the view, inside the Thunar window"
xdotool key Escape
sleep 0.5

xdotool key ctrl+2
sleep 1
go_to "$APPS"
click_first_row
f2
Q=$(find_window '^Rename Launcher Options$') || fail "F2 on launcher.desktop did not ask whether to rename the launcher or the file"
transient_for_main "$Q" "The Rename Launcher Options question"
shot root launcher-question "F2 on launcher.desktop opens the Rename Launcher Options question over the Thunar window, as its transient dialog"
focus "$Q"
xdotool key Escape
sleep 0.5

shot root before-dbus-dialog "Thunar shows the apps folder with notes.txt and no rename UI open, before a rename is requested over D-Bus"
dbus-send --session --print-reply --reply-timeout=60000 --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.RenameFile string:"file://$APPS/notes.txt" string:"" string:"" >/dev/null 2>&1 &
DBUS=$!
D=$(find_window '^Rename "notes.txt"$') || fail "RenameFile over D-Bus did not open the rename dialog"
transient_for_main "$D" "The rename dialog opened over D-Bus"
shot root after-dbus-dialog "RenameFile over D-Bus opened the rename dialog as before, transient for the Thunar window and on top of it"
pair dbus-dialog "Called org.xfce.FileManager.RenameFile for notes.txt over D-Bus" "With no view to attach to, the rename dialog is kept, opened over the Thunar window" "no rename UI" "rename dialog over Thunar" "$O"
focus "$D"
xdotool type --delay 20 renamed-over-dbus
xdotool key Return
exists "$APPS/renamed-over-dbus.txt" "renaming in the D-Bus dialog"
wait "$DBUS" || fail "the D-Bus RenameFile call failed"
