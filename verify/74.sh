#!/bin/bash
# Issue #74: the status bar always shows the folder's totals and free space, and no byte counts by default.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1100
H=600
DIR="$WORK/files"
G='Status bar: totals and free space, no byte counts'

mkdir -p "$DIR/sub"
truncate -s 1M "$DIR/a.bin"
truncate -s 2M "$DIR/b.bin"
truncate -s 3M "$DIR/c.bin"
echo trash > "$WORK/trashed.txt"

clear_selection() {
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 80)) click 1
  sleep 1
}

select_one() {
  clear_selection
  xdotool key Home Down
  sleep 1
}

select_two() {
  select_one
  xdotool key shift+Down
  sleep 1
}

search() {
  clear_selection
  xdotool key ctrl+f
  sleep 0.5
  xdotool type --delay 20 bin
  sleep 3
}

cancel_search() {
  focus "$WID"
  xdotool key Escape
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

open_thunar "$DIR"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" files
focus "$WID"
xdotool key ctrl+2
sleep 1

clear_selection
shot "$WID" after-status-none "Default settings, nothing selected: the status bar reads 1 folder | 3 files: 6.0 MiB | Free space: …, with no (… bytes)"
select_one
shot "$WID" after-status-one "Default settings, a.bin selected: \"a.bin\" | 1.0 MiB | its type | Total: 1 folder, 3 files: 6.0 MiB | Free space: …"
select_two
shot "$WID" after-status-many "Default settings, a.bin and b.bin selected: Selection: 2 files: 3.0 MiB | Total: 1 folder, 3 files: 6.0 MiB | Free space: …"
search
shot "$WID" after-status-search "Searching for bin: the status bar reads 3 files found: 6.0 MiB | Free space: …, with no Total part"
cancel_search
go "$DIR" files

xfconf-query -c thunar -p /misc-status-bar-active-info -n -t uint -s 15
select_one
clear_selection
shot "$WID" before-status-none "Size in bytes switched on, as in the old default: nothing selected shows 3 files: 6.0 MiB (6,291,456 bytes)"
pair status-none "Went from Size in bytes on (the old default) to the new default" "With nothing selected the new default drops the byte count and keeps the folder totals and free space" "Old default: 6.0 MiB (6,291,456 bytes)" "New default: 6.0 MiB, no byte count" "$G"
select_one
shot "$WID" before-status-one "Size in bytes on, a.bin selected: its size reads 1.0 MiB (1,048,576 bytes)"
pair status-one "Selected a.bin, with Size in bytes on and then with the new default" "One selected file keeps Total and Free space, and the new default drops its byte count" "Old default: 1.0 MiB (1,048,576 bytes)" "New default: 1.0 MiB | Total | Free space" "$G"
select_two
shot "$WID" before-status-many "Size in bytes on, a.bin and b.bin selected: Selection: 2 files: 3.0 MiB (3,145,728 bytes)"
pair status-many "Selected a.bin and b.bin, with Size in bytes on and then with the new default" "A multi-file selection keeps Total and Free space, and the new default drops the byte count" "Old default: 3.0 MiB (3,145,728 bytes)" "New default: 3.0 MiB | Total | Free space" "$G"
search
shot "$WID" after-status-bytes-on "Size in bytes switched back on while searching: 3 files found: 6.0 MiB (6,291,456 bytes) | Free space: …"
cancel_search
go "$DIR" files
xfconf-query -c thunar -p /misc-status-bar-active-info -r || true

gio trash "$WORK/trashed.txt" || fail "could not move a file to the trash"
go trash:/// Trash
select_one
shot "$WID" after-status-trash "Trash with trashed.txt selected: its name, type, original path and Total: 1 file, with no Free space part"
kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar quit after selecting a file in the trash"

go "$DIR" files
clear_selection
xdotool key --delay 15 Home Down Down Down Up Down Up
sleep 3
shot "$WID" after-status-rapid "After quick selection changes ending on b.bin: \"b.bin\" | 2.0 MiB | its type | Total: … | Free space: …, nothing from an earlier selection"
kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar is no longer running"
exit 0
