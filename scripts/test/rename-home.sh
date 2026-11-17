#!/bin/sh
# guest/layer/usr/lib/harborplay/rename-home on a throw-away home: the steamac data folders move to harborplay,
# the old names become links, installed.json's backup path follows, a second run changes nothing, and an existing
# harborplay folder is never overwritten.
#   docker run --rm -v "$PWD":/src:ro harborplay-image-builder:4 sh /src/scripts/test/rename-home.sh
S=$(cd "$(dirname "$0")/../.." && pwd)/guest/layer/usr/lib/harborplay/rename-home
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT; fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
for d in .config .local/state .local/share; do mkdir -p "$H/$d/steamac" && echo "$d" > "$H/$d/steamac/data"; done
mkdir -p "$H/.local/state/steamac/fex-eac"
echo "{\"backup\": \"$H/.local/state/steamac/fex-eac/valve\"}" > "$H/.local/state/steamac/fex-eac/installed.json"
sh "$S" "$H" >/dev/null
for d in .config .local/state .local/share; do
  check "$d moved" '[ "$(cat "$H/$d/harborplay/data")" = "$d" ]'
  check "$d old name links to harborplay" '[ "$(readlink "$H/$d/steamac")" = harborplay ]'
done
check "installed.json backup path follows" 'grep -q "/.local/state/harborplay/fex-eac/valve" "$H/.local/state/harborplay/fex-eac/installed.json"'
before=$(ls -lR "$H"); sh "$S" "$H" >/dev/null
check "second run changes nothing" '[ "$(ls -lR "$H")" = "$before" ]'
rm "$H/.config/steamac"; mkdir "$H/.config/steamac"; echo old > "$H/.config/steamac/data"
sh "$S" "$H" >/dev/null
check "existing harborplay folder kept" '[ "$(cat "$H/.config/harborplay/data")" = .config ] && [ "$(cat "$H/.config/steamac/data")" = old ]'
[ $fail = 0 ] && echo "rename-home: all PASS"
exit $fail
