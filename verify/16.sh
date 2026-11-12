#!/bin/bash
# Issue #16: F2 on one file edits its name in place, in the details, icon and compact views, with misc-rename-in-place on (the default).
set -euo pipefail
. .github/scripts/verify-lib.sh

ROW0=$((103 + (EUID == 0 ? 34 : 0)))
NAME_X=230
DIR="$WORK/files"
APPS="$WORK/apps"

mkdir -p "$DIR" "$APPS"
echo a > "$DIR/alpha.txt"
echo r > "$DIR/report.final.pdf"
echo t > "$DIR/taken.pdf"
for i in $(seq -w 1 30); do echo "$i" > "$DIR/zz-$i.txt"; done
cat > "$APPS/launcher.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Launcher
Exec=true
EOF
echo n > "$APPS/notes.txt"
echo o > "$APPS/other.txt"
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

D='Rename in place in the details view'
V='Other views and settings'

exists() {
  local i
  for ((i = 0; i < 25; i++)); do
    [[ -e $1 ]] && return 0
    sleep 0.2
  done
  fail "$2: $(basename "$1") does not exist; the folder holds: $(ls "$(dirname "$1")" | tr '\n' ' ')"
}

absent() {
  local i
  for ((i = 0; i < 10; i++)); do
    [[ ! -e $1 ]] && return 0
    sleep 0.2
  done
  fail "$2: $(basename "$1") still exists"
}

no_window() {
  ! xdotool search --onlyvisible --name "$1" >/dev/null 2>&1 || fail "$2 opened a '$1' window"
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

keys() {
  focus "$MAIN"
  xdotool key "$@"
  sleep 0.5
}

click_first_row() {
  local i
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" 500 400
  for ((i = 0; i < 12; i++)); do xdotool click 4; done
  sleep 0.5
  xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
  sleep 0.3
  xdotool click 1
  sleep 0.5
  xdotool mousemove --window "$MAIN" 500 560
}

second_row() {
  click_first_row
  keys Down
}

f2() {
  keys F2
  sleep 0.5
}

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" 1000 600
xdotool windowmove --sync "$MAIN" 0 0
wait_title "$MAIN" files

second_row
shot "$MAIN" before-entry "The details view with report.final.pdf, the second row, selected and no rename UI open"
f2
no_window '^Rename ' "F2 on report.final.pdf"
shot "$MAIN" after-entry "F2 turned report.final.pdf's Name cell into a text entry inside the row, with 'report.final' selected but not '.pdf', and no popover or dialog"
pair entry "Selected report.final.pdf and pressed F2" "F2 edits the name in place, with the name selected without its extension" "report.final.pdf selected" "entry in the Name cell, 'report.final' selected" "$D"
xdotool type --delay 20 summary
xdotool key Return
exists "$DIR/summary.pdf" "typing summary over the selected 'report.final' and Enter"
absent "$DIR/report.final.pdf" "after renaming report.final.pdf in place"

sleep 0.5
keys ctrl+z
exists "$DIR/report.final.pdf" "Ctrl+Z after the in-place rename"
absent "$DIR/summary.pdf" "Ctrl+Z after the in-place rename"

second_row
f2
xdotool type --delay 20 escaped
xdotool key Escape
sleep 0.5
absent "$DIR/escaped.pdf" "Escape in the entry"
exists "$DIR/report.final.pdf" "Escape in the entry"

second_row
f2
xdotool key ctrl+a BackSpace Return
sleep 0.5
shot "$MAIN" empty-name "Enter on an empty name left the entry open in report.final.pdf's row, marked with an error icon, and renamed nothing"
xdotool type --delay 20 'bad/name'
xdotool key Return
sleep 0.5
shot "$MAIN" slash-name "Enter on 'bad/name' left the entry open with the error icon, and renamed nothing"
xdotool key Escape
sleep 0.5
exists "$DIR/report.final.pdf" "an empty name, 'bad/name' and Escape"
[[ ! -e $DIR/bad ]] || fail "Enter on 'bad/name' created the folder bad"

second_row
f2
xdotool key ctrl+a
xdotool type --delay 20 taken.pdf
xdotool key Return
E=$(find_window '^Error$') || fail "renaming report.final.pdf to the existing taken.pdf showed no error"
shot root rename-error "Renaming report.final.pdf to the existing taken.pdf shows Thunar's 'Failed to rename' error dialog over the window"
focus "$E"
xdotool key Return
sleep 0.5
exists "$DIR/report.final.pdf" "after the failed rename to taken.pdf"
shot "$MAIN" name-restored "After the error, the second row shows report.final.pdf again and no entry is left open"

second_row
f2
xdotool key ctrl+a
xdotool type --delay 20 clicked.pdf
xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
sleep 0.3
xdotool click 1
exists "$DIR/clicked.pdf" "typing clicked.pdf and clicking another row"
absent "$DIR/report.final.pdf" "typing clicked.pdf and clicking another row"

xdotool mousemove --window "$MAIN" 500 400
for i in 1 2 3 4 5 6; do
  xdotool click 5
  sleep 0.1
done
sleep 0.8
shot "$MAIN" before-scroll-in "alpha.txt, the first row, is selected, and the mouse wheel scrolled it far out of view above"
f2
shot "$MAIN" after-scroll-in "F2 scrolled alpha.txt back into view, with its Name cell turned into an entry and 'alpha' selected"
pair scroll-in "Selected alpha.txt, scrolled it out of view with the wheel, pressed F2" "F2 on a row out of view scrolls it in before editing its name" "selected row far out of view" "row scrolled in, name in an entry" "$D"
xdotool key Escape
sleep 0.5

xfconf-query -c thunar -p /last-details-view-column-order -n -t string \
  -s THUNAR_COLUMN_SIZE,THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE_IN_BYTES,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_MODIFIED
sleep 1
second_row
shot "$MAIN" before-moved-column "The Size column is now first and Name second; clicked.pdf is selected"
f2
shot "$MAIN" after-moved-column "F2 opened the entry in the Name column, the second one, not in the Size column, with 'clicked' selected"
pair moved-column "Moved the Size column before Name, selected clicked.pdf, pressed F2" "The entry opens in the Name column wherever it is" "Size first, clicked.pdf selected" "entry in the Name column" "$D"
xdotool key ctrl+a
xdotool type --delay 20 moved.pdf
xdotool key Return
exists "$DIR/moved.pdf" "renaming with the Name column second"
xfconf-query -c thunar -p /last-details-view-column-order -r
sleep 0.5

second_row
xdotool key Menu
sleep 0.8
xdotool key r
sleep 1
no_window '^Rename ' "Rename... in the context menu"
shot "$MAIN" context-menu "Rename... in moved.pdf's context menu turned its Name cell into an entry with 'moved' selected, like F2"
xdotool type --delay 20 from-menu
xdotool key Return
exists "$DIR/from-menu.pdf" "Rename... from the context menu, typing from-menu and Enter"
sleep 0.5
click_first_row

keys ctrl+1
sleep 0.5
f2
no_window '^Rename ' "F2 in the icon view"
shot "$MAIN" icon-view "In the icon view, with alpha.txt still selected from the details view, F2 turned alpha.txt's label into an entry under its icon, with 'alpha' selected"
xdotool type --delay 20 icon-renamed
xdotool key Return
exists "$DIR/icon-renamed.txt" "renaming alpha.txt in the icon view"

keys ctrl+3
sleep 0.5
f2
no_window '^Rename ' "F2 in the compact view"
shot "$MAIN" compact-view "In the compact view, with icon-renamed.txt still selected, F2 turned icon-renamed.txt's label into an entry beside its icon, with 'icon-renamed' selected"
xdotool type --delay 20 compact-renamed
xdotool key Return
exists "$DIR/compact-renamed.txt" "renaming icon-renamed.txt in the compact view"

keys ctrl+1
sleep 0.5
keys End
f2
shot "$MAIN" icon-view-scrolled "End selected zz-30.txt, the last item, and scrolled the icon view to the bottom; F2 turned zz-30.txt's own label into an entry, with 'zz-30' selected"
xdotool key Escape
sleep 0.5
absent "$DIR/zz-30" "Escape in the icon view"

keys ctrl+2
sleep 0.5
xfconf-query -c thunar -p /misc-rename-in-place -n -t bool -s false
sleep 0.5
second_row
shot "$MAIN" before-preference-off "With Rename files in place turned off, from-menu.pdf is selected in the details view"
f2
shot "$MAIN" after-preference-off "F2 opened the rename popover added by issue 15 below from-menu.pdf instead of an entry in its row"
pair preference-off "Turned misc-rename-in-place off, selected from-menu.pdf, pressed F2" "With the preference off, F2 opens the rename popover as before" "preference off, from-menu.pdf selected" "rename popover below from-menu.pdf" "$V"
xdotool key Escape
sleep 0.5
xfconf-query -c thunar -p /misc-rename-in-place -s true

focus "$MAIN"
xdotool key ctrl+l
sleep 0.3
xdotool type --delay 5 "$APPS"
xdotool key Return
wait_title "$MAIN" apps
sleep 0.5
click_first_row
f2
Q=$(find_window '^Rename Launcher Options$') || fail "F2 on launcher.desktop did not ask whether to rename the launcher or the file"
shot root launcher-question "F2 on launcher.desktop still asks Rename Launcher Options in a dialog instead of editing in place"
focus "$Q"
xdotool key Escape
sleep 0.5

keys ctrl+a
f2
B=$(find_window '^Rename Multiple Files$') || fail "F2 on three selected files did not open the bulk rename dialog"
shot root bulk-rename "F2 with three files selected still opens the Rename Multiple Files dialog"
focus "$B"
xdotool key Escape
sleep 0.5

dbus-send --session --print-reply --reply-timeout=60000 --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.RenameFile string:"file://$APPS/notes.txt" string:"" string:"" >/dev/null 2>&1 &
DBUS=$!
R=$(find_window '^Rename "notes.txt"$') || fail "RenameFile over D-Bus did not open the rename dialog"
shot root dbus-dialog "RenameFile over D-Bus still opens the rename dialog for notes.txt"
focus "$R"
xdotool type --delay 20 renamed-over-dbus
xdotool key Return
exists "$APPS/renamed-over-dbus.txt" "renaming in the D-Bus dialog"
wait "$DBUS" || fail "the D-Bus RenameFile call failed"

dbus-send --session --print-reply --dest=org.xfce.FileManager /org/xfce/FileManager \
  org.xfce.FileManager.DisplayPreferencesDialog string:"" string:"" >/dev/null 2>&1 || fail "could not open the preferences over D-Bus"
P=$(find_window '^Thunar Preferences$') || fail "the preferences dialog did not open"
focus "$P"
xdotool key ctrl+Page_Down ctrl+Page_Down
sleep 0.5
shot "$P" preferences "The Behavior tab of Thunar Preferences has a checked 'Rename files in place' option under Navigation"
xdotool key Escape
