#!/bin/bash
# Issue #144: the status bar keeps folder totals and free space instead of re-reading every file on each selection change.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1100
H=600
DIR="$WORK/many"
G='Status bar: cached totals, free space and search size'

mib() { awk -v b="$1" 'BEGIN { printf "%.1f MiB", b / 1048576 }'; }

mkdir -p "$DIR"
for ((i = 1; i <= 2000; i++)); do
  : > "$DIR/$(printf 'f%04d' "$i")"
done
truncate -s 1M "$DIR/a.bin"
truncate -s 1M "$DIR/grow.bin"
hits=0
for ((i = 1; i <= 40; i++)); do
  truncate -s $((i * 12345)) "$DIR/$(printf 'hit-%02d.dat' "$i")"
  hits=$((hits + i * 12345))
done
total=$((2 * 1048576 + hits))
grown=$((total + 1048576))

TRACE=''
if command -v strace >/dev/null; then
  TRACE="$WORK/trace"
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\nexec strace -D -f -s 4096 -e trace=%%%%stat -o "%s" "%s" "$@"\n' "$TRACE" "$(command -v thunar)" > "$WORK/bin/thunar"
  chmod +x "$WORK/bin/thunar"
  PATH="$WORK/bin:$PATH"
else
  echo "strace is not installed: skipping the stat count, keeping the functional checks"
fi

clear_selection() {
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 80)) click 1
  sleep 0.3
  xdotool key Escape
  sleep 1
}

select_a() {
  clear_selection
  xdotool key ctrl+a
  sleep 0.3
  xdotool key Home
  sleep 1
}

open_thunar "$DIR"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" many
focus "$WID"
xdotool key ctrl+2
sleep 2

select_a
if [[ -n $TRACE ]]; then
  [[ -s $TRACE ]] || fail "strace wrote no trace"
  start=$(wc -l < "$TRACE")
fi
for ((i = 0; i < 20; i++)); do
  xdotool key Down
  sleep 0.3
done
sleep 1
if [[ -n $TRACE ]]; then
  stats=$(tail -n +"$((start + 1))" "$TRACE" | grep -c "\"$DIR/" || true)
  echo "stat calls on files in the folder during 20 selection changes: $stats"
  (( stats < 2000 )) || fail "20 selection changes made $stats stat calls on the folder's files, expected far fewer than 20 x 2042"
fi
kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar quit while the selection changed"
shot "$WID" status-after-keys "After 20 Down presses from a.bin, f0020 is selected: \"f0020\" | 0 bytes on the left, 2042 files: $(mib "$total") | Free space: … on the right"

select_a
shot "$WID" before-grow "a.bin selected before grow.bin grows: the right part reads 2042 files: $(mib "$total") | Free space: …"
head -c 1048576 /dev/zero >> "$DIR/grow.bin"
sleep 4
shot "$WID" after-grow "a.bin still selected, 4 s after the script appended 1 MiB to grow.bin: the right part reads 2042 files: $(mib "$grown") | Free space: …"
pair grow "Appended 1 MiB to grow.bin while a.bin stayed selected" "The cached folder total updates when a file in the folder grows, without a selection change" "Total $(mib "$total")" "Total $(mib "$grown")" "$G"

clear_selection
xdotool key ctrl+f
sleep 0.5
xdotool type --delay 20 hit-
sleep 4
shot "$WID" status-search "Searching for hit-: the status bar reads 40 files found: $(mib "$hits") | Free space: …, the sum of the 40 hit-NN.dat sizes ($hits bytes)"
kill -0 "$THUNAR_PID" 2>/dev/null || fail "Thunar is no longer running"
exit 0
