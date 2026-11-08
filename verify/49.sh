#!/bin/bash
# Issue #49: in list view with Expandable folders on, Shift and Ctrl with Up/Down extend or keep the selection.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ROW0=$((103 + (EUID == 0 ? 34 : 0)))
ROW_H=${ROW_H:-26}
NAME_X=239
DIR="$WORK/files"

mkdir -p "$DIR/folder"
for f in file1 file2 file3 file4 file5 file6; do echo "$f" > "$DIR/$f"; done
for f in inner1 inner2 inner3; do echo "$f" > "$DIR/folder/$f"; done

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /misc-expandable-folders -n -t bool -s true

click_row() {  # row index, 0 being the first row (folder)
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$NAME_X" $((ROW0 + $1 * ROW_H))
  sleep 0.3
  xdotool click 1
  sleep 0.3
}

keys() {
  focus "$MAIN"
  local k
  for k in "$@"; do
    xdotool key "$k"
    sleep 0.2
  done
  sleep 0.3
}

N=0
selected_is() {  # the names the selection must hold
  local dest got want i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  keys ctrl+c
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | sort | tr '\n' ' ')
    [[ $got == "$want" ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "$want" ]] || fail "check $N: the selection held '$got', expected '$want'"
}

S='Shift+Up/Down extend the selection'
C='Ctrl+Up/Down keep the selection'
E='Expanded folders'
U='Unchanged keys'

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" "$W" "$H"
wait_title "$MAIN" files
sleep 1

# Shift+Down from file1 (rows: 0 folder, 1 file1 ... 6 file6)
click_row 1
selected_is file1
shot "$MAIN" before-shift-down "List view with Expandable folders on: file1 is clicked and is the only selected row (status bar: file1 selected)"
keys shift+Down shift+Down
selected_is file1 file2 file3
shot "$MAIN" after-shift-down "Two Shift+Down presses from file1 selected file1, file2 and file3 (status bar: 3 files selected)"
pair shift-down "Clicked file1, then pressed Shift+Down twice" "Shift+Down extends the selection from the clicked row instead of moving it" "file1 selected" "file1-file3 selected" "$S"

keys shift+Up
selected_is file1 file2
shot "$MAIN" shift-up-shrinks "Shift+Up after that shrank the selection back to file1 and file2 (status bar: 2 files selected)"

click_row 3
keys shift+Up shift+Up
selected_is file1 file2 file3
shot "$MAIN" shift-up-from-below "Clicking file3 and pressing Shift+Up twice selected file1 to file3, with the anchor on file3 below"

click_row 1
keys shift+Down shift+Down Down Up shift+Down
selected_is file3 file4

# Ctrl+Down moves only the cursor; Ctrl+Space adds the cursor row
click_row 1
shot "$MAIN" before-ctrl-down "file1 is clicked and is the only selected row"
keys ctrl+Down ctrl+Down ctrl+space
selected_is file1 file3
shot "$MAIN" after-ctrl-down "Ctrl+Down twice kept file1 selected and moved only the cursor; Ctrl+Space added file3 (2 files selected, file2 not)"
pair ctrl-down "Clicked file1, pressed Ctrl+Down twice, then Ctrl+Space" "Ctrl+Down moves only the cursor, so Ctrl+Space can add a second, separate row" "file1 selected" "file1 and file3 selected, file2 not" "$C"

# Shift+Down across an expanded folder selects its children
click_row 0
keys Right
sleep 1
shot "$MAIN" before-expanded "The folder row is clicked and expanded with Right: inner1, inner2 and inner3 show under it, above file1"
keys shift+Down shift+Down shift+Down shift+Down
selected_is folder inner1 inner2 inner3 file1
shot "$MAIN" after-expanded "Four Shift+Down presses selected folder, its children inner1 to inner3 and file1 (5 items selected)"
pair expanded "Expanded folder, then pressed Shift+Down four times from it" "Shift+Down steps into the expanded folder and selects its children, never a placeholder" "folder expanded, folder selected" "folder, inner1-3 and file1 selected" "$E"

# Plain keys behave as before: Down selects one row, Left collapses, Enter opens
keys Down
selected_is file2
keys Up Up
selected_is inner3
keys Left
selected_is folder
keys Left Down
selected_is file1
shot "$MAIN" plain-keys "Plain keys still move a single selection: Left went from inner3 to folder, Left again collapsed it, and Down selected only file1"
keys Up Return
wait_title "$MAIN" folder
shot "$MAIN" enter-opens "Enter on the folder row still opens the folder: the window shows inner1, inner2 and inner3"

# Expandable folders off: GTK's own handling, unchanged
xfconf-query -c thunar -p /misc-expandable-folders -s false
keys BackSpace
wait_title "$MAIN" files
sleep 1
click_row 1
keys shift+Down shift+Down
selected_is file1 file2 file3
shot "$MAIN" expandable-off "With Expandable folders off (no expanders), Shift+Down twice from file1 still selects file1 to file3"
