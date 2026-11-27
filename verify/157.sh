#!/bin/bash
# Issue #157: the rename job renames on its worker thread but swaps the file's info on the main thread, so 30 quick F2
# renames in a row leave Thunar running, each new name on disk and Ctrl+Z still undoing the last one, and 10 renames
# from one Properties dialog, which watches its file, keep the dialog open on the new name.
set -euo pipefail
. .github/scripts/verify-lib.sh

DIR="$WORK/files"
PDIR="$WORK/props"
N=30
P=10
G='Rename in place many times in a row (#157)'

mkdir -p "$DIR" "$PDIR"
echo a > "$DIR/a00.txt"
echo p > "$PDIR/p00.txt"
for i in 1 2 3 4 5; do echo "$i" > "$DIR/m-$i.txt"; done
xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView

exists() {
  local i
  for ((i = 0; i < 50; i++)); do
    [[ -e $1 ]] && return 0
    sleep 0.1
  done
  fail "$2: $(basename "$1") does not exist; the folder holds: $(ls "$(dirname "$1")" | tr '\n' ' ')"
}

running() {
  kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar is no longer running $1"
}

open_thunar "$DIR"
MAIN=$WID
xdotool windowsize --sync "$MAIN" 1000 600
xdotool windowmove --sync "$MAIN" 0 0
wait_title "$MAIN" files
focus "$MAIN"
xdotool key Home
sleep 0.5
shot "$MAIN" before-renames "The details view of files with a00.txt, the first row, selected and the five m-*.txt files below it"

for ((n = 1; n <= N; n++)); do
  old=$(printf 'a%02d.txt' $((n - 1)))
  new=$(printf 'a%02d.txt' "$n")
  focus "$MAIN"
  xdotool key Home F2
  sleep 0.5
  xdotool type --delay 5 "${new%.txt}"
  xdotool key Return
  exists "$DIR/$new" "rename $n, $old to $new in place"
  [[ ! -e $DIR/$old ]] || fail "rename $n left $old on disk next to $new"
  running "after rename $n, $old to $new"
done

sleep 1
running "1 s after the last rename"
LAST=$(printf 'a%02d.txt' "$N")
[[ $(ls "$DIR" | grep -c '^a[0-9]*\.txt$') == 1 ]] || fail "the folder should hold only $LAST of the renamed files; it holds: $(ls "$DIR" | tr '\n' ' ')"
focus "$MAIN"
xdotool key Home
sleep 0.5
shot "$MAIN" after-renames "After $N in-place renames in a row Thunar is still open, and the first row shows $LAST, selected, above the five m-*.txt files"
pair renames "Renamed a00.txt in place $N times in a row: F2, the new name without .txt, Enter" \
  "Quick in-place renames no longer crash Thunar; each one renames the file on disk and in the view" \
  "a00.txt selected" "Thunar still open, $LAST in the first row" "$G"

PREV=$(printf 'a%02d.txt' $((N - 1)))
focus "$MAIN"
xdotool key ctrl+z
exists "$DIR/$PREV" "Ctrl+Z after the last in-place rename"
[[ ! -e $DIR/$LAST ]] || fail "Ctrl+Z after the last in-place rename left $LAST on disk"
running "after Ctrl+Z"
sleep 0.5
focus "$MAIN"
xdotool key Home
shot "$MAIN" undo "Ctrl+Z undid the last in-place rename: the first row shows $PREV again, from the rename job's operation log entry"

focus "$MAIN"
xdotool key ctrl+l
xdotool type --delay 5 "$PDIR"
xdotool key Return
wait_title "$MAIN" props
sleep 0.5
xdotool key Home alt+Return
D=""
for ((i = 0; i < 50; i++)); do
  D=$(xdotool search --onlyvisible --name '^p00\.txt - Properties$' 2>/dev/null | head -1) || true
  [[ -n $D ]] && break
  sleep 0.2
done
[[ -n $D ]] || fail "Alt+Return on p00.txt did not open its Properties dialog"

for ((n = 1; n <= P; n++)); do
  old=$(printf 'p%02d.txt' $((n - 1)))
  new=$(printf 'p%02d.txt' "$n")
  focus "$D"
  xdotool key ctrl+a
  xdotool type --delay 5 "$new"
  xdotool key Return
  exists "$PDIR/$new" "Properties rename $n, $old to $new"
  [[ ! -e $PDIR/$old ]] || fail "Properties rename $n left $old on disk next to $new"
  running "after Properties rename $n, $old to $new"
  wait_title "$D" "$new - Properties"
done

sleep 1
running "1 s after the last Properties rename"
PLAST=$(printf 'p%02d.txt' "$P")
xdotool getwindowname "$D" >/dev/null 2>&1 || fail "the Properties dialog closed after $P renames"
shot "$D" properties "After $P renames in a row from its Name field, the Properties dialog is still open, titled $PLAST - Properties, with $PLAST in the Name field"
