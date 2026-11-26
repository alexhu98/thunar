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
  for ((i = 0; i < 50; i++)); do
    dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
      string:org.xfce.Thunar 2>/dev/null | grep -q 'boolean false' && break
    sleep 0.1
  done
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

measure() {  # png, where, [gap to the search button, default 5]: sets TOG_X, TOG_Y, TOG_START, TOG_END, TOG_TOP, TOG_ROWS, ENTRY_END and GAPS, and fails unless the gaps match +-1
  local right=${3:-5} found mid y entry_end gap_l tog_start tog_end gap_r
  found=$(toggle_rows "$1")
  [[ -n $found ]] || fail "$2: found no row with the search entry, a gap, the Include subfolders toggle, a gap and the search button"
  found=$(awk '{ w = $5 - $4; if (w > max) max = w; r[NR] = $0; ws[NR] = w } END { for (i = 1; i <= NR; i++) if (ws[i] == max) print r[i] }' <<<"$found")
  mid=$(sed -n "$(( ($(wc -l <<<"$found") + 1) / 2 ))p" <<<"$found")
  read -r y entry_end gap_l tog_start tog_end gap_r <<<"$mid"
  TOG_X=$(( (tog_start + tog_end) / 2 ))
  TOG_Y=$y
  TOG_START=$tog_start
  TOG_END=$tog_end
  TOG_TOP=$(head -n 1 <<<"$found" | cut -d' ' -f1)
  TOG_ROWS=$(( $(tail -n 1 <<<"$found" | cut -d' ' -f1) - TOG_TOP + 1 ))
  ENTRY_END=$entry_end
  GAPS="entry border ends at x=$entry_end, toggle x=$tog_start-$tog_end on row y=$y: entry to toggle $gap_l px, toggle to search button $gap_r px"
  echo "$2: $GAPS"
  (( gap_l >= 4 && gap_l <= 6 )) || fail "$2: the gap from the search entry to the toggle is $gap_l px, expected 5 +-1 ($GAPS)"
  (( gap_r >= right - 1 && gap_r <= right + 1 )) || fail "$2: the gap from the toggle to the search button is $gap_r px, expected $right +-1 ($GAPS)"
}

no_toggle() {  # png, where: fails unless, in some row of the toggle measured while searching, one colour runs from inside
               # the entry's border then to inside the toggle's place, as the entry does when it reaches over that place
  local clean
  clean=$(convert "$1" -crop "$((TOG_END - ENTRY_END + 2))x$TOG_ROWS+$((ENTRY_END - 4))+$TOG_TOP" +repage -depth 8 txt:- \
    | awk 'NR > 1 { split($1, p, /[,:]/); y = p[2]; if (!(y in c)) c[y] = $2; else if ($2 != c[y]) bad[y] = 1 }
        END { for (y in c) if (!(y in bad)) n++; print n + 0 }')
  (( clean > 0 )) || fail "$2: no row of x=$((ENTRY_END - 4))-$((TOG_END - 3)), y=$TOG_TOP-$((TOG_TOP + TOG_ROWS - 1)) is one colour, so the entry doesn't reach over the Include subfolders toggle's place and the toggle shows although no search is running"
}

crop() {  # shot name, what it shows: keeps the right end of the toolbar around the toggle, enlarged 4 times so the gaps
          # are visible, and adds that and what it shows to the shot's line in shots.tsv
  convert "$SHOTS/$1.png" -crop "$((W - TOG_X + 260))x64+$((TOG_X - 260))+$((TOG_Y > 32 ? TOG_Y - 32 : 0))" +repage \
    -filter point -resize 400% "$SHOTS/$1.png" || fail "could not crop $1"
  awk -F'\t' -v OFS='\t' -v name="$1" -v more="; cropped to the right end of the toolbar and enlarged 4 times: $2" \
    '$1 == name { $2 = $2 more } 1' "$SHOTS/shots.tsv" > "$WORK/shots.tsv" && mv "$WORK/shots.tsv" "$SHOTS/shots.tsv"
}

G='The toggle sits 5 px from the search entry'

start_thunar top
shot "$WID" before-toggle-gap "The right end of Thunar's toolbar before a search"
search
shot "$WID" after-toggle-gap "The right end of Thunar's toolbar while searching, with the Include subfolders toggle showing"
measure "$SHOTS/after-toggle-gap.png" "menu bar shown"
SHOWN_GAPS=$GAPS
no_toggle "$SHOTS/before-toggle-gap.png" "menu bar shown, not searching"
pair toggle-gap "Pressed Ctrl+F and typed match" "The Include subfolders toggle appears with a gap on both sides ($GAPS)" "no search, no toggle" "toggle, a gap to the entry and the button" "$G"

click_toggle
capture "$WORK/released.png"
measure "$WORK/released.png" "menu bar shown, toggle released"
PART="[30x20+$((TOG_X - 15))+$((TOG_Y - 10))]"
[[ $(compare -metric AE "$SHOTS/after-toggle-gap.png$PART" "$WORK/released.png$PART" null: 2>&1 || true) =~ ^[1-9][0-9]*$ ]] \
  || fail "clicking the Include subfolders toggle did not change how it looks"
crop before-toggle-gap "no Include subfolders toggle; the script checked that the entry reaches over its place"
crop after-toggle-gap "a gap of toolbar background on each side of the pressed toggle, measured as $SHOWN_GAPS"
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
  [[ -n $(ls -A "$WORK/top/pasted") ]] && break
  sleep 0.2
done
sleep 2
[[ $(ls -A "$WORK/top/pasted") == match-top.txt ]] \
  || fail "with the toggle released the search listed '$(ls -A "$WORK/top/pasted" | tr '\n' ' ')', expected only match-top.txt"

restart_thunar hidden last-menubar-visible false
capture "$WORK/hidden-idle.png"
search
shot "$WID" menubar-hidden-gap "The right end of Thunar's toolbar with the menu bar hidden, while searching, with the Include subfolders toggle showing"
measure "$SHOTS/menubar-hidden-gap.png" "menu bar hidden"
no_toggle "$WORK/hidden-idle.png" "menu bar hidden, not searching"
crop menubar-hidden-gap "a gap on each side of the pressed toggle, measured as $GAPS"

restart_thunar csd misc-use-csd true
capture "$WORK/csd-idle.png"
search
shot "$WID" headerbar-gap "The right end of Thunar's header bar with client-side decorations on, while searching, with the Include subfolders toggle showing"
measure "$SHOTS/headerbar-gap.png" "header bar" 15
no_toggle "$WORK/csd-idle.png" "header bar, not searching"
crop headerbar-gap "a gap from the search entry to the pressed toggle, and from the toggle to the search button, measured as $GAPS"
