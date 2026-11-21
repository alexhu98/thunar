#!/bin/bash
# Issue #132: the status bar shows the selection on the left and the folder total and free space on the right.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1200
NARROW=800
H=600
DIR="$WORK/files"
OTHER="$WORK/other"
LONG=z-a-long-name-the-selection-keeps.txt
G='Status bar: selection left, folder total and free space right'

EMPTY="$WORK/empty"

mkdir -p "$DIR/sub" "$OTHER" "$EMPTY"
truncate -s 1M "$DIR/b.bin"
truncate -s 2M "$DIR/c.bin"
echo text > "$DIR/$LONG"
truncate -s 5M "$OTHER/only.bin"

clear_selection() {
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 4)) $((H - 80)) click 1
  sleep 1
}

select_first_file() {
  clear_selection
  xdotool key ctrl+a
  sleep 0.3
  xdotool key Home Down
  sleep 1
}

select_long() {
  clear_selection
  xdotool key ctrl+a
  sleep 0.3
  xdotool key End
  sleep 1
}

go() {  # location, expected title
  focus "$WID"
  xdotool key ctrl+l
  sleep 0.3
  xdotool type --delay 5 "$1"
  xdotool key Return
  wait_title "$WID" "$2"
  xdotool key Escape
  sleep 0.5
}

width_of() {
  xdotool getwindowgeometry "$1" | sed -n 's/.*Geometry: \([0-9]*\)x.*/\1/p'
}

open_thunar "$DIR"
xdotool windowmove --sync "$WID" 0 0
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" files
focus "$WID"
xdotool key ctrl+2
sleep 1

clear_selection
shot "$WID" status-none "Nothing selected: the left of the status bar is empty, and 1 folder, 3 files: … | Free space: … sits against the right edge"

select_first_file
shot "$WID" status-one "b.bin selected: \"b.bin\" | 1.0 MiB | its type on the left, and 1 folder, 3 files: 3.0 MiB | Free space: … on the right, with no word Total"

select_long
shot "$WID" before-narrow "Wide window, the long .txt file selected: its name, size and type on the left, the folder total and free space in full on the right"
xdotool windowsize --sync "$WID" "$NARROW" "$H"
sleep 1
got=$(width_of "$WID")
(( got <= NARROW + 10 )) || fail "window is $got px wide after resizing to $NARROW px: the status bar raised its minimum width"
shot "$WID" after-narrow "Narrow window, same selection: the long name, size and type are still shown in full on the left, and only the right part is cut short with …"
pair narrow "Narrowed the window from $W px to $NARROW px with the long-named file selected" "When both parts don't fit, the selection keeps its full width and only the folder total and free space are shortened with …" "Wide: both parts in full" "Narrow: selection in full, right part cut short" "$G"

xdotool windowsize --sync "$WID" "$W" "$H"
sleep 1
clear_selection
xdotool key ctrl+t
sleep 1
go "$OTHER" other
sleep 1
shot "$WID" status-tab-other "New tab on folder other: the right part follows the active tab and reads 1 file: 5.0 MiB | Free space: …"
xdotool key ctrl+Page_Up
wait_title "$WID" files
sleep 1
shot "$WID" status-tab-back "Back on the first tab, nothing selected: the right part reads the files folder's 1 folder, 3 files: … | Free space: … again, in the same format as with a selection"

go "$EMPTY" empty
sleep 1
shot "$WID" status-empty "Empty folder: the left of the status bar is empty, and the right part reads 0 items | Free space: …"

focus "$WID"
xdotool key ctrl+1
sleep 1
go "$DIR" files
sleep 1
shot "$WID" status-icon-view "Icon view, back on folder files with nothing selected: the left of the status bar is empty, and the right part reads 1 folder, 3 files: … | Free space: …"

kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar is no longer running"
exit 0
