#!/bin/bash
# Issue #68: a 5 px gap between the search entry and the Include subfolders toggle.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=700
ROWS=160

for dir in top hidden csd; do
  mkdir -p "$WORK/$dir/sub"
  echo top > "$WORK/$dir/match-top.txt"
  echo sub > "$WORK/$dir/sub/match-sub.txt"
done

restart_thunar() {  # folder, xfconf property, value...
  local dir=$1
  shift
  kill "$THUNAR_PID" 2>/dev/null || fail "Thunar was no longer running before the restart"
  wait "$THUNAR_PID" 2>/dev/null || true
  unset THUNAR_PID
  while (( $# )); do
    xfconf-query -c thunar -p "/$1" -n -t bool -s "$2"
    shift 2
  done
  start_thunar "$dir"
}

click_toggle() {
  xdotool mousemove --window "$WID" "$TOG_X" "$TOG_Y"
  sleep 0.5
  xdotool click 1
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 40))
  sleep 2
}

start_thunar() {  # folder
  open_thunar "$WORK/$1"
  xdotool windowsize --sync "$WID" "$W" "$H"
  wait_title "$WID" "$1"
  focus "$WID"
  xdotool mousemove --window "$WID" $((W / 2)) $((H - 40))
  sleep 0.5
}

search() {
  focus "$WID"
  xdotool key ctrl+f
  sleep 0.5
  xdotool type --delay 20 match
  sleep 2
}

capture() {  # file
  sleep 1
  import -window "$WID" "$1" || fail "could not capture window $WID"
}

toggle_rows() {  # png: prints "y entry-end gap-left toggle-start toggle-end gap-right" for each row through the toggle
  convert "$1" -crop "${W}x${ROWS}+0+0" +repage -depth 8 txt:- | awk -v w="$W" '
    function row(   i, n, s, b, k, st, en, br) {
      n = 0
      for (i = 0; i < w; i++) {
        b = (i in bright) ? bright[i] : 0
        if (i == 0 || b != br[n]) { n++; st[n] = i; br[n] = b }
        en[n] = i
      }
      for (k = 1; k + 5 <= n; k++) {
        if (br[k] || en[k] - st[k] + 1 < 100) continue
        if (en[k+1] - st[k+1] + 1 > 4) continue
        if (en[k+2] - st[k+2] + 1 > 20 || en[k+4] - st[k+4] + 1 > 20) continue
        if (en[k+3] - st[k+3] + 1 < 20 || en[k+3] - st[k+3] + 1 > 50) continue
        if (en[k+5] - st[k+5] + 1 < 20) continue
        printf "%d %d %d %d %d %d\n", y, en[k+1], en[k+2] - st[k+2] + 1, st[k+3], en[k+3], en[k+4] - st[k+4] + 1
        return
      }
    }
    NR > 1 {
      split($1, p, /[,:]/)
      if (p[2] != y && NR > 2) { row(); delete bright }
      y = p[2]
      c = $2; gsub(/[()]/, "", c); split(c, v, ",")
      m = v[1]; if (v[2] > m) m = v[2]; if (v[3] > m) m = v[3]
      bright[p[1]] = (m >= 64)
    }
    END { row() }'
}

measure() {  # png, where, [gap to the search button, default 5]: sets TOG_X, TOG_Y and GAPS, and fails unless the gaps match +-1
  local right=${3:-5} found mid y entry_end gap_l tog_start tog_end gap_r
  found=$(toggle_rows "$1")
  [[ -n $found ]] || fail "$2: found no row with the search entry, a gap, the Include subfolders toggle, a gap and the search button"
  found=$(awk '{ w = $5 - $4; if (w > max) max = w; r[NR] = $0; ws[NR] = w } END { for (i = 1; i <= NR; i++) if (ws[i] == max) print r[i] }' <<<"$found")
  mid=$(sed -n "$(( ($(wc -l <<<"$found") + 1) / 2 ))p" <<<"$found")
  read -r y entry_end gap_l tog_start tog_end gap_r <<<"$mid"
  TOG_X=$(( (tog_start + tog_end) / 2 ))
  TOG_Y=$y
  GAPS="entry border ends at x=$entry_end, toggle x=$tog_start-$tog_end on row y=$y: entry to toggle $gap_l px, toggle to search button $gap_r px"
  echo "$2: $GAPS"
  (( gap_l >= 4 && gap_l <= 6 )) || fail "$2: the gap from the search entry to the toggle is $gap_l px, expected 5 +-1 ($GAPS)"
  (( gap_r >= right - 1 && gap_r <= right + 1 )) || fail "$2: the gap from the toggle to the search button is $gap_r px, expected $right +-1 ($GAPS)"
}

no_toggle() {  # png, where
  local found
  found=$(toggle_rows "$1")
  [[ -z $found ]] || fail "$2: the Include subfolders toggle is showing although no search is running (row $(head -n 1 <<<"$found"))"
}

crop() {  # shot name: keeps the right end of the toolbar around the toggle, enlarged 4 times so the gaps are visible
  convert "$SHOTS/$1.png" -crop "$((W - TOG_X + 260))x64+$((TOG_X - 260))+$((TOG_Y > 32 ? TOG_Y - 32 : 0))" +repage \
    -filter point -resize 400% "$SHOTS/$1.png" || fail "could not crop $1"
}

G='The toggle sits 5 px from the search entry'

start_thunar top
capture "$WORK/idle.png"
no_toggle "$WORK/idle.png" "menu bar shown, not searching"
shot "$WID" before-toggle-gap "Toolbar with the menu bar shown, enlarged 4 times, before a search: the location bar shows the path of top and there is no Include subfolders toggle"
search
capture "$WORK/searching.png"
measure "$WORK/searching.png" "menu bar shown"
shot "$WID" after-toggle-gap "Toolbar with the menu bar shown, enlarged 4 times, while searching for match: a 5 px gap of toolbar background separates the search entry's border from the pressed Include subfolders toggle, the same as the gap from the toggle to the search button"
crop before-toggle-gap
crop after-toggle-gap
pair toggle-gap "Pressed Ctrl+F and typed match" "The Include subfolders toggle appears with a 5 px gap on both sides ($GAPS)" "no search, no toggle" "toggle, 5 px from the entry and the button" "$G"

click_toggle
capture "$WORK/released.png"
measure "$WORK/released.png" "menu bar shown, toggle released"
[[ $(compare -metric AE -crop 30x20+$((TOG_X - 15))+$((TOG_Y - 10)) "$WORK/searching.png" "$WORK/released.png" null: 2>&1 || true) != 0 ]] \
  || fail "clicking the Include subfolders toggle did not change how it looks"
xdotool mousemove --window "$WID" $((W / 2)) $((H - 100)) click 1
sleep 0.5
xdotool key ctrl+a
sleep 0.5
xdotool key ctrl+c
sleep 0.5
focus "$WID"
xdotool key Escape
sleep 1
capture "$WORK/cancelled.png"
no_toggle "$WORK/cancelled.png" "menu bar shown, search cancelled"
mkdir -p "$WORK/top/pasted"
focus "$WID"
xdotool key ctrl+l
sleep 0.3
xdotool type --delay 5 "$WORK/top/pasted"
xdotool key Return
wait_title "$WID" pasted
xdotool key Escape
sleep 0.5
xdotool key ctrl+v
for ((i = 0; i < 25; i++)); do
  [[ $(ls -A "$WORK/top/pasted") == match-top.txt ]] && break
  sleep 0.2
done
[[ $(ls -A "$WORK/top/pasted") == match-top.txt ]] \
  || fail "with the toggle released the search listed '$(ls -A "$WORK/top/pasted" | tr '\n' ' ')', expected only match-top.txt"

restart_thunar hidden last-menubar-visible false
capture "$WORK/hidden-idle.png"
no_toggle "$WORK/hidden-idle.png" "menu bar hidden, not searching"
search
capture "$WORK/hidden-searching.png"
measure "$WORK/hidden-searching.png" "menu bar hidden"
shot "$WID" menubar-hidden-gap "Toolbar with the menu bar hidden, enlarged 4 times, while searching for match: the pressed Include subfolders toggle has a 5 px gap to the search entry and to the search button ($GAPS)"
crop menubar-hidden-gap

restart_thunar csd misc-use-csd true
capture "$WORK/csd-idle.png"
no_toggle "$WORK/csd-idle.png" "header bar, not searching"
search
capture "$WORK/csd-searching.png"
measure "$WORK/csd-searching.png" "header bar" 15
shot "$WID" headerbar-gap "Header bar with the menu bar hidden and client-side decorations on, enlarged 4 times, while searching for match: the pressed Include subfolders toggle is 5 px from the search entry, and the search button keeps the header bar's 15 px location bar margin ($GAPS)"
crop headerbar-gap
