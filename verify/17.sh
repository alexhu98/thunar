#!/bin/bash
# Issue #17: the side pane has a Bookmarks section, and Places shows the standard folders.
set -euo pipefail
. .github/scripts/verify-lib.sh

W=1000
H=760
PANE_X=70
TOP_Y=84
STEP=10

CONF=${XDG_CONFIG_HOME:-$HOME/.config}
mkdir -p "$CONF/gtk-3.0" "$HOME/Desktop" "$HOME/Documents" "$HOME/Music" \
  "$WORK/data/Downloads" "$WORK/data/Videos" "$WORK/projects" "$WORK/notes" "$WORK/start"
echo marker > "$WORK/data/Downloads/in-data-downloads.txt"
ln -s "$WORK/data/Downloads" "$HOME/Downloads"
ln -s "$WORK/data/Videos" "$HOME/Videos"
cat > "$CONF/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF
printf 'file://%s\nfile://%s\n' "$WORK/projects" "$WORK/notes" > "$CONF/gtk-3.0/bookmarks"
BOOKMARKS_BEFORE=$(cat "$CONF/gtk-3.0/bookmarks")


title() { local t; t=$(xdotool getwindowname "$WID"); echo "${t%% - *}"; }

scan() {
  local y t prev
  NAMES=() YS=()
  focus "$WID"
  prev=$(title)
  for ((y = TOP_Y; y < H - 10; y += STEP)); do
    xdotool mousemove --window "$WID" "$PANE_X" "$y" click 1
    sleep 0.25
    t=$(title)
    [[ $t == "$prev" ]] && continue
    NAMES+=("$t") YS+=("$y")
    prev=$t
    [[ $t != "File System" && $t != / ]] || return 0
  done
  fail "side pane scan reached the bottom without a Devices row; it opened: ${NAMES[*]}"
}

index_of() {
  local i
  for i in "${!NAMES[@]}"; do [[ ${NAMES[$i]} == "$1" ]] && { echo "$i"; return; }; done
  echo -1
}

y_of() { local i; i=$(index_of "$1"); ((i >= 0)) || fail "$1 is not in the side pane: ${NAMES[*]}"; echo "${YS[$i]}"; }

before() {
  local a b
  a=$(index_of "$1") b=$(index_of "$2")
  ((a >= 0 && b >= 0 && a < b)) || fail "expected $1 before $2 in the side pane: ${NAMES[*]}"
}

hidden_has() {
  xfconf-query -c thunar -p /hidden-bookmarks 2>/dev/null | grep -qxF "$1" \
    || fail "$1 is not in hidden-bookmarks: $(xfconf-query -c thunar -p /hidden-bookmarks 2>&1)"
}

hidden_lacks() {
  ! xfconf-query -c thunar -p /hidden-bookmarks 2>/dev/null | grep -qxF "$1" \
    || fail "$1 is in hidden-bookmarks: $(xfconf-query -c thunar -p /hidden-bookmarks 2>&1)"
}

toggle() {
  local y=$(($1 - 12)) i
  focus "$WID"
  xdotool mousemove --window "$WID" "$PANE_X" "$y" click 3
  sleep 0.6
  for ((i = 0; i < $2; i++)); do xdotool key Down; done
  xdotool key Right
  for ((i = 1; i < $3; i++)); do xdotool key Down; done
  sleep 0.5
  [[ -z ${4:-} ]] || shot root "$4" "$5"
  xdotool key Return
  sleep 0.8
}

open_thunar "$WORK/start"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" start
sleep 1

scan
echo "side pane: ${NAMES[*]} at y ${YS[*]}"
for name in Desktop Documents Downloads Music Videos projects notes; do
  [[ $(index_of "$name") -ge 0 ]] || fail "$name is not in the side pane: ${NAMES[*]}"
done
before Desktop Documents
before Documents Downloads
before Downloads Music
before Music Videos
[[ $(printf '%s\n' "${NAMES[@]}" | grep -cxF "$(basename "$HOME")") -eq 1 ]] || fail "the home folder is not listed exactly once: ${NAMES[*]}"
before Videos projects
before projects notes
[[ $(index_of Trash) -lt 0 ]] || before Trash projects
[[ $(index_of Recent) -lt 0 ]] || before Videos Recent
before notes "${NAMES[-1]}"

xdotool mousemove --window "$WID" "$PANE_X" "$(y_of Downloads)" click 1
wait_title "$WID" Downloads
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" before-hide-bookmarks "Places lists Desktop, Documents, Downloads, Music and Videos before Trash, without Pictures, which is set to the home folder, then a Bookmarks header over projects and notes, then Devices; Downloads is open and shows in-data-downloads.txt, the file in the folder its symlink points to"


toggle "$(y_of projects)" 2 1 bookmarks-menu "The Bookmarks header's right-click menu is open on its Bookmarks submenu, which lists projects and notes, each with a checked show/hide box"
hidden_has "file://$WORK/projects"
toggle "$(y_of projects)" 2 2
hidden_has "file://$WORK/notes"
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" after-hide-bookmarks "With projects and notes hidden, the Bookmarks header is gone too: Places is followed directly by the Devices header"
pair hide-bookmarks "Unticked projects, then notes, in the Bookmarks header's right-click menu" "Bookmarks can be hidden from their header's menu, and the header hides when every bookmark is hidden" "Bookmarks: projects, notes" "Both hidden: no Bookmarks header" "Bookmarks section"
[[ $(cat "$CONF/gtk-3.0/bookmarks") == "$BOOKMARKS_BEFORE" ]] || fail "hiding bookmarks changed the bookmarks file"

DL=$(($(index_of Downloads) + 1))
printf 'file://%s\n' "$HOME/Downloads" >> "$CONF/gtk-3.0/bookmarks"
sleep 2
scan
[[ $(printf '%s\n' "${NAMES[@]}" | grep -cxF Downloads) -eq 2 ]] || fail "the Downloads bookmark didn't appear next to the Places row: ${NAMES[*]}"
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" before-hide-downloads "Downloads is listed twice: in Places between Documents and Music, and under the Bookmarks header that came back for the new Downloads bookmark"
toggle "${YS[0]}" 1 "$DL"
hidden_has "places:file://$HOME/Downloads"
hidden_lacks "file://$HOME/Downloads"

kill "$THUNAR_PID"
for ((i = 0; i < 50; i++)); do kill -0 "$THUNAR_PID" 2>/dev/null || break; sleep 0.2; done
unset THUNAR_PID
open_thunar "$WORK/start"
xdotool windowsize --sync "$WID" "$W" "$H"
wait_title "$WID" start
sleep 1
scan
echo "side pane after restart: ${NAMES[*]}"
for name in projects notes; do
  [[ $(index_of "$name") -lt 0 ]] || fail "$name came back after a restart: ${NAMES[*]}"
done
before Documents Music
before Videos Downloads
[[ $(printf '%s\n' "${NAMES[@]}" | grep -cxF Downloads) -eq 1 ]] || fail "Downloads should be listed once, as a bookmark: ${NAMES[*]}"
xdotool mousemove --window "$WID" $((W - 100)) $((H - 100))
shot "$WID" after-hide-downloads "After a restart Places goes from Documents straight to Music, without Downloads, while the Downloads bookmark still shows under the Bookmarks header; projects and notes stay hidden"
pair hide-downloads "Unticked Downloads in the Places submenu, then quit and restarted Thunar" "Hiding a standard folder doesn't hide a bookmark to the same folder, and stays hidden after a restart" "Downloads in Places and Bookmarks" "Restarted: only the bookmark shows" "Standard folders"
