#!/bin/bash
# Issue #16: F2 on one file edits its name in place in the details view, with misc-rename-in-place on (the default); the icon and compact views keep the popover.
set -euo pipefail
. .github/scripts/verify-lib.sh

ROW0=$((103 + (EUID == 0 ? 34 : 0)))
NAME_X=230
DIR="$WORK/files"

mkdir -p "$DIR"
echo a > "$DIR/alpha.txt"
echo r > "$DIR/report.final.pdf"
echo t > "$DIR/taken.pdf"
for i in $(seq -w 1 30); do echo "$i" > "$DIR/zz-$i.txt"; done
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

D='Rename in place in the details view'

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
  sleep 0.3
}

click_first_row() {
  local i
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" 500 400
  for ((i = 0; i < 12; i++)); do xdotool click 4; done
  sleep 0.3
  xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
  xdotool click 1
  sleep 0.3
  xdotool mousemove --window "$MAIN" 500 560
}

second_row() {
  click_first_row
  keys Down
}

f2() {
  keys F2
  sleep 0.4
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
xdotool type --delay 10 summary
xdotool key Return
exists "$DIR/summary.pdf" "typing summary over the selected 'report.final' and Enter"
absent "$DIR/report.final.pdf" "after renaming report.final.pdf in place"

keys ctrl+z
exists "$DIR/report.final.pdf" "Ctrl+Z after the in-place rename"
absent "$DIR/summary.pdf" "Ctrl+Z after the in-place rename"

second_row
f2
xdotool type --delay 10 escaped
xdotool key Escape
absent "$DIR/escaped.pdf" "Escape in the entry"
exists "$DIR/report.final.pdf" "Escape in the entry"

keys alt+Up
wait_title "$MAIN" "$(basename "$WORK")"
keys ctrl+l
xdotool type --delay 5 "$DIR"
xdotool key Return
wait_title "$MAIN" files
sleep 0.5
second_row
f2
xdotool key ctrl+a BackSpace Return
xdotool type --delay 10 'bad/name'
xdotool key Return
xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
xdotool click 8
sleep 0.5
[[ $(xdotool getwindowname "$MAIN") == *files* ]] || fail "the back button with 'bad/name' in the entry left the folder: the title is '$(xdotool getwindowname "$MAIN")'"
shot "$MAIN" invalid-name "After an empty name, then 'bad/name' with Enter, then the mouse back button, the entry is still open in report.final.pdf's row with the error icon, and the folder is unchanged"
xdotool key Escape
exists "$DIR/report.final.pdf" "an empty name, 'bad/name', the back button and Escape"
[[ ! -e $DIR/bad ]] || fail "Enter on 'bad/name' created the folder bad"

second_row
f2
xdotool key ctrl+a
xdotool type --delay 10 taken.pdf
xdotool key Return
E=$(find_window '^Error$') || fail "renaming report.final.pdf to the existing taken.pdf showed no error"
shot root rename-error "Renaming report.final.pdf to the existing taken.pdf shows Thunar's 'Failed to rename' error dialog over the window"
focus "$E"
xdotool key Return
exists "$DIR/report.final.pdf" "after the failed rename to taken.pdf"

second_row
f2
xdotool key ctrl+a
xdotool type --delay 10 clicked.pdf
xdotool mousemove --window "$MAIN" "$NAME_X" "$ROW0"
xdotool click 1
exists "$DIR/clicked.pdf" "typing clicked.pdf and clicking another row"
absent "$DIR/report.final.pdf" "typing clicked.pdf and clicking another row"

xfconf-query -c thunar -p /last-details-view-column-order -n -t string \
  -s THUNAR_COLUMN_SIZE,THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE_IN_BYTES,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_MODIFIED
sleep 0.5
second_row
f2
shot "$MAIN" moved-column "With the Size column first and Name second, F2 on clicked.pdf opened the entry in the Name column, not in the Size column, with 'clicked' selected"
xdotool key ctrl+a
xdotool type --delay 10 moved.pdf
xdotool key Return
exists "$DIR/moved.pdf" "renaming with the Name column second"
xfconf-query -c thunar -p /last-details-view-column-order -r
sleep 0.3

second_row
xdotool key Menu
sleep 0.5
xdotool key r
sleep 0.5
no_window '^Rename ' "Rename... in the context menu"
xdotool type --delay 10 from-menu
xdotool key Return
exists "$DIR/from-menu.pdf" "Rename... from the context menu, typing from-menu and Enter"
click_first_row

keys ctrl+1
f2
no_window '^Rename ' "F2 in the icon view"
shot "$MAIN" icon-view "In the icon view, with alpha.txt still selected from the details view, F2 opened the rename popover with 'alpha' selected instead of editing in place"
xdotool type --delay 10 icon-renamed
xdotool key Return
exists "$DIR/icon-renamed.txt" "renaming alpha.txt in the icon view"

keys ctrl+2
xfconf-query -c thunar -p /misc-rename-in-place -n -t bool -s false
sleep 0.3
second_row
f2
shot "$MAIN" preference-off "With Rename files in place turned off, F2 on from-menu.pdf opened the rename popover added by issue 15 below it instead of an entry in its row"
xdotool key Escape
xfconf-query -c thunar -p /misc-rename-in-place -s true
