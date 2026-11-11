#!/bin/bash
# Issue #89: with Sort folders before files on, folders are always in natural name order, A to Z, whatever the sort.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ROW0=$((103 + (EUID == 0 ? 34 : 0)))
ROW_H=${ROW_H:-26}
NAME_X=239
DIR="$WORK/files"

mkdir -p "$DIR/Alpha" "$DIR/dir2" "$DIR/dir10"
head -c 4000 /dev/zero > "$DIR/Alpha/big"
head -c 100 /dev/zero > "$DIR/dir10/small"
head -c 3000 /dev/zero > "$DIR/c.txt"
head -c 2000 /dev/zero > "$DIR/a.txt"
head -c 100 /dev/zero > "$DIR/b.txt"
touch -d '2020-01-01' "$DIR/dir10"
touch -d '2021-01-01' "$DIR/Alpha"
touch -d '2022-01-01' "$DIR/dir2"
touch -d '2020-06-01' "$DIR/b.txt"
touch -d '2021-06-01' "$DIR/c.txt"
touch -d '2022-06-01' "$DIR/a.txt"

xfconf-query -c thunar -p /default-view -n -t string -s ThunarDetailsView
xfconf-query -c thunar -p /misc-folders-first -n -t bool -s true

N=0
row_is() {
  local row=$1 want=$2 dest got i
  N=$((N + 1))
  dest="$WORK/check-$N"
  mkdir -p "$dest"
  focus "$MAIN"
  xdotool mousemove --window "$MAIN" "$NAME_X" $((ROW0 + row * ROW_H))
  sleep 0.3
  xdotool click 1
  sleep 0.3
  xdotool key ctrl+c
  sleep 0.3
  open_thunar "$dest"
  wait_title "$WID" "check-$N"
  focus "$WID"
  xdotool key ctrl+v
  for ((i = 0; i < 25; i++)); do
    got=$(ls -A "$dest" | tr '\n' ' ')
    [[ $got == "$want " ]] && break
    sleep 0.2
  done
  xdotool key ctrl+w
  sleep 0.5
  WID=$MAIN
  [[ $got == "$want " ]] || fail "check $N: row $row is '$got', expected '$want'"
}

order_is() {
  local row=0 name
  for name in "$@"; do
    row_is "$row" "$name"
    row=$((row + 1))
  done
}

launch() {
  if [[ -n ${THUNAR_PID:-} ]]; then
    thunar -q || true
    wait "$THUNAR_PID" 2>/dev/null || true
    unset THUNAR_PID
  fi
  xfconf-query -c thunar -p /last-sort-column -n -t string -s "$1"
  xfconf-query -c thunar -p /last-sort-order -n -t string -s "$2"
  open_thunar "$DIR"
  MAIN=$WID
  xdotool windowsize --sync "$MAIN" "$W" "$H"
  wait_title "$MAIN" files
  sleep 1
}

G='Folders stay in name order'

launch THUNAR_COLUMN_NAME GTK_SORT_ASCENDING
order_is Alpha dir2 dir10 a.txt b.txt c.txt
shot "$MAIN" before-size-desc "Sorted by Name ascending: folders Alpha, dir2, dir10 first, then files a.txt, b.txt, c.txt"

launch THUNAR_COLUMN_SIZE GTK_SORT_DESCENDING
order_is Alpha dir2 dir10 c.txt a.txt b.txt
shot "$MAIN" after-size-desc "Sorted by Size descending: folders still Alpha, dir2, dir10; files by size, largest first: c.txt, a.txt, b.txt"
pair size-desc "Switched the sort from Name ascending to Size descending" "Folders keep natural A to Z name order while the files follow Size descending" "Name A-Z: Alpha dir2 dir10, a b c" "Size desc: Alpha dir2 dir10, c a b" "$G"

launch THUNAR_COLUMN_DATE_MODIFIED GTK_SORT_ASCENDING
order_is Alpha dir2 dir10 b.txt c.txt a.txt
shot "$MAIN" date-modified "Sorted by Date Modified ascending: folders still Alpha, dir2, dir10 (by date they would be dir10, Alpha, dir2); files oldest first: b.txt, c.txt, a.txt"

launch THUNAR_COLUMN_NAME GTK_SORT_DESCENDING
order_is Alpha dir2 dir10 c.txt b.txt a.txt
shot "$MAIN" name-desc "Sorted by Name descending: folders stay A to Z (Alpha, dir2, dir10) while files go Z to A: c.txt, b.txt, a.txt"

xfconf-query -c thunar -p /misc-folders-first -s false
launch THUNAR_COLUMN_NAME GTK_SORT_DESCENDING
order_is dir10 dir2 c.txt b.txt Alpha a.txt
shot "$MAIN" folders-first-off "With Sort folders before files off, Name descending mixes folders and files Z to A as before: dir10, dir2, c.txt, b.txt, Alpha, a.txt"
