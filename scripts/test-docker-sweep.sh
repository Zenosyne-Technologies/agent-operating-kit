#!/usr/bin/env bash
# test-docker-sweep.sh — behavioural tests for scripts/marvin-docker-sweep.sh (AOS-216).
# A fake `docker` first on PATH serves the fixture listings the suite writes per test and logs
# every call; a removal it accepts lands in rmlog. The fake IGNORES the label filter on purpose, so
# the sweep's own project-label re-check is what keeps another project's resource safe. One
# fixture per keep-guard (D1–D6) asserting its NAMED reason and no removal, removal of each kind,
# removal order, multi-tag images kept, scope, --check, --hook and docker-missing. The mutation section reverts each guard
# in a copy: a mutation counts as caught only when the fixture passes on the real script, the
# mutant run exits 0, and the fixture then fails.
# Run from anywhere: bash scripts/test-docker-sweep.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SWEEP="$SCRIPT_DIR/marvin-docker-sweep.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-dstest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

R="$WORK/repo"; WT="$R/.claude/worktrees"; FX="$WORK/fx"; FAKE="$WORK/fake"; SYS="$WORK/sys"
mkdir -p "$FAKE" "$SYS"

# ── the fake docker ────────────────────────────────────────────────────────────────────────────
cat > "$FAKE/docker" <<'SH'
#!/usr/bin/env bash
# fixture files in $DOCKER_FX: containers (id name state project checkout owner lifetime), networks /
# images (id name project checkout owner lifetime; an image's name is its comma-joined tags), volumes
# (name name project checkout owner lifetime) — tab-separated;
# down, lsfail-<kind>, inspectfail, inspectnl, rmfail (id lists) steer failures.
FX=${DOCKER_FX:?}
printf '%s\n' "$*" >> "$FX/calls"
case "${1:-}" in
  info|version) [ -f "$FX/down" ] && exit 1; exit 0 ;;
  container|network|volume|image) kind=$1; verb=${2:-}; shift 2 ;;
  *) exit 1 ;;
esac
id=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in --format|--filter) skip=1 ;; -*) ;; *) [ -n "$id" ] || id=$a ;; esac
done
file="$FX/${kind}s"
case "$verb" in
  ls)
    [ -f "$FX/lsfail-$kind" ] && exit 1
    [ -f "$file" ] && cut -f1 "$file"; exit 0 ;;
  inspect)
    grep -qxF -- "$id" "$FX/inspectfail" 2>/dev/null && exit 1
    line=$(awk -F'\t' -v id="$id" '$1 == id { print; exit }' "$file" 2>/dev/null)
    [ -n "$line" ] || exit 1
    printf '%s\n' "${line#*	}"
    grep -qxF -- "$id" "$FX/inspectnl" 2>/dev/null && printf 'x\tother\n'
    exit 0 ;;
  rm)
    grep -qxF -- "$id" "$FX/rmfail" 2>/dev/null && exit 1
    printf '%s %s\n' "$kind" "$id" >> "$FX/rmlog"; exit 0 ;;
esac
exit 1
SH
chmod +x "$FAKE/docker"

# a PATH without any docker, for the docker-missing fixtures
for c in bash env git awk od basename dirname cat head sed grep cut tr timeout; do
  p=$(command -v "$c" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$SYS/$c"
done

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
has()   { printf '%s\n' "$OUT" | grep -Fq -- "$1"; }
rmd()   { I="$1" awk '$2 == ENVIRON["I"] { f = 1 } END { exit !f }' "$FX/rmlog" 2>/dev/null; }   # rmd <id> — the fake removed it
assert_rc()     { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1"; fi; }
assert_out()    { if has "$1"; then ok "out has: $1"; else bad "out lacks: $1 (got: $(printf '%s' "$OUT" | head -c 300))"; fi; }
assert_no_out() { if has "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 200)"; fi; }
assert_rm()     { if rmd "$1"; then ok "removed: $1"; else bad "not removed: $1"; fi; }
assert_no_rm()  { if rmd "$1"; then bad "wrongly removed: $1"; else ok "not removed: $1"; fi; }
assert_lines()  { local n; n=$(printf '%s\n' "$OUT" | grep -c .); if [ "$n" = "$1" ]; then ok "$1 line(s)"; else bad "$n line(s), want $1"; fi; }

CKV=""
fresh() {  # a Marvin repo named "repo" (P=repo), its worktrees dir, empty fixtures; CKV = its marvin.checkout
  rm -rf "$R" "$FX"; mkdir -p "$FX"; git init -q "$R"; mkdir -p "$R/.marvin" "$WT"
  : > "$FX/calls"; : > "$FX/rmlog"
  CKV=$(git -C "$R" worktree list --porcelain | sed -n '1s/^worktree //p')   # tidying.md's C line
}
# the checkout label is the last, optional argument — default: this checkout
ctr() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${7-$CKV}" "$5" "$6" >> "$FX/containers"; }  # id name state project owner lifetime [checkout]
net() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${6-$CKV}" "$4" "$5" >> "$FX/networks"; }            # id name project owner lifetime [checkout]
vol() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$1" "$2" "${5-$CKV}" "$3" "$4" >> "$FX/volumes"; }             # name project owner lifetime [checkout]
img() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${6-$CKV}" "$4" "$5" >> "$FX/images"; }              # id tags project owner lifetime [checkout]
sweep() {  # sweep <script> [args…] — run from the main checkout with the fake docker first on PATH
  local s="$1"; shift
  OUT=$(cd "$R" && PATH="$FAKE:$PATH" DOCKER_FX="$FX" CLAUDE_PROJECT_DIR="$R" "$BASH" "$s" "$@" </dev/null 2>&1); RC=$?
}

# ── guard fixtures (fx_*) and their silent checks (ck_*), shared with the mutation section ────────
fx_D0() { fresh; vol v0a repo gone throwaway ""; vol v0b repo gone throwaway /elsewhere/repo; vol v0c repo gone throwaway "$CKV/"; sweep "$1"; }
ck_D0() { has "kept: volume v0a — D0 another checkout" && has "kept: volume v0b — D0 another checkout" \
          && has "kept: volume v0c — D0 another checkout" && ! rmd v0a && ! rmd v0b && ! rmd v0c; }
fx_D1() { fresh; vol v1 repo gone keep; sweep "$1"; }
ck_D1() { has "kept: volume v1 — D1 lifetime keep" && ! rmd v1; }
fx_D2() { fresh; vol v2 repo main throwaway; ctr c2 c2name exited repo "" throwaway; sweep "$1"; }
ck_D2() { has "kept: volume v2 — D2 owned by the main checkout" && has "kept: container c2name — D2 owned by the main checkout" && ! rmd v2 && ! rmd c2; }
fx_D3() { fresh; vol v3a repo .. throwaway; vol v3b repo a/b throwaway; vol v3c repo . throwaway; sweep "$1"; }
ck_D3() { has "kept: volume v3a — D3 owner label invalid" && has "kept: volume v3b — D3 owner label invalid" \
          && has "kept: volume v3c — D3 owner label invalid" && ! rmd v3a && ! rmd v3b && ! rmd v3c; }
fx_D4() { fresh; mkdir -p "$WT/wt1"; vol v4 repo wt1 throwaway; sweep "$1"; }
ck_D4() { has "kept: volume v4 — D4 owner worktree still present" && ! rmd v4; }
fx_D4L() { fresh; ln -s "$WORK/nowhere" "$WT/wt2"; vol v4l repo wt2 throwaway; sweep "$1"; }   # a dangling symlink
ck_D4L() { has "kept: volume v4l — D4 owner worktree still present" && ! rmd v4l; }
fx_D5() { fresh; ctr c5 c5run running repo gone throwaway; ctr c5p c5pause paused repo gone throwaway; sweep "$1"; }
ck_D5() { has "kept: container c5run — D5 container running" && has "kept: container c5pause — D5 container running" && ! rmd c5 && ! rmd c5p; }
fx_D6() { fresh; ctr c6 c6busy exited repo gone throwaway; echo c6 > "$FX/rmfail"; sweep "$1"; }
ck_D6() { has "kept: container c6busy — D6 docker refused (in use)" && ! rmd c6; }
fx_PROJ() { fresh; ctr cx cxname exited other gone throwaway; vol vx repo-x gone throwaway; net nx nxname "" gone throwaway; sweep "$1"; }
ck_PROJ() { ! has cxname && ! has vx && ! has nxname && ! rmd cx && ! rmd vx && ! rmd nx; }
fx_D7() { fresh; img sha256:9999aaaabbbbcccc "m:a,m:b,m:c" repo gone throwaway; sweep "$1"; }
ck_D7() { has 'kept: image "m:a" — D7 several tags — untag it by hand' && ! rmd sha256:9999aaaabbbbcccc && [ ! -s "$FX/rmlog" ]; }
orphans() {  # one orphaned throwaway of each kind (owner worktree gone), listed images-first
  img sha256:aaaabbbbccccdddd1111 "" repo gone throwaway
  img sha256:aaaabbbbccccdddd1111 "" repo gone throwaway   # a second tag row: listed twice, removed once
  img sha256:eeee2222 "app:t" repo gone throwaway
  vol vgone repo gone throwaway
  net ngone ngname repo gone throwaway
  ctr cgone cgname exited repo gone throwaway
}

hd "D0 a resource of another checkout with the same directory name is kept (checkout label absent, other, or not byte-equal)"
if [ "$(fresh; printf '%s' "$CKV")" = "$R" ]; then ok "the checkout label value is the main checkout path"; else bad "checkout label value differs from $R"; fi
fx_D0 "$SWEEP"; assert_rc 0; assert_out "kept: volume v0a — D0 another checkout"; assert_out "kept: volume v0b — D0 another checkout"
assert_out "kept: volume v0c — D0 another checkout"; assert_no_rm v0a; assert_no_rm v0b; assert_no_rm v0c

hd "D1 a resource whose lifetime is not throwaway is kept"
fx_D1 "$SWEEP"; assert_rc 0; assert_out "kept: volume v1 — D1 lifetime keep"; assert_no_rm v1

hd "D2 a main-owned (or owner-less) throwaway is kept"
fx_D2 "$SWEEP"; assert_rc 0; assert_out "kept: volume v2 — D2 owned by the main checkout"
assert_out "kept: container c2name — D2 owned by the main checkout"; assert_no_rm v2; assert_no_rm c2

hd "D3 an owner label of .., . or a/b is invalid"
fx_D3 "$SWEEP"; assert_rc 0; assert_out "kept: volume v3a — D3 owner label invalid"
assert_out "kept: volume v3b — D3 owner label invalid"; assert_out "kept: volume v3c — D3 owner label invalid"
assert_no_rm v3a; assert_no_rm v3b; assert_no_rm v3c

hd "D4 the owner worktree still present keeps it — a directory, or a symlink (even dangling)"
fx_D4 "$SWEEP"; assert_rc 0; assert_out "kept: volume v4 — D4 owner worktree still present"; assert_no_rm v4
fx_D4L "$SWEEP"; assert_out "kept: volume v4l — D4 owner worktree still present"; assert_no_rm v4l

hd "D5 a running or paused container is kept"
fx_D5 "$SWEEP"; assert_rc 0; assert_out "kept: container c5run — D5 container running"
assert_out "kept: container c5pause — D5 container running"; assert_no_rm c5; assert_no_rm c5p

hd "D6 docker refusing the removal keeps it and never aborts the sweep"
fx_D6 "$SWEEP"; vol v6 repo gone throwaway; sweep "$SWEEP"; assert_rc 0
assert_out "kept: container c6busy — D6 docker refused (in use)"; assert_no_rm c6; assert_rm v6

hd "S1 a resource labelled for another project is never listed or removed (the fake ignores the filter)"
fx_PROJ "$SWEEP"; assert_rc 0; assert_empty; assert_no_rm cx; assert_no_rm vx; assert_no_rm nx

hd "R1 an orphaned throwaway of each kind is removed, in order, images de-duplicated"
fresh; orphans; sweep "$SWEEP"; assert_rc 0
assert_out "removed: container cgname"; assert_out "removed: network ngname"; assert_out "removed: volume vgone"
assert_out 'removed: image "app:t"'; assert_out "removed: image aaaabbbbcccc"
order=$(awk '{ print $1 }' "$FX/rmlog" | awk '!s[$0]++' | tr '\n' ' ')
if [ "$order" = "container network volume image " ]; then ok "order containers → networks → volumes → images"; else bad "order: $order"; fi
if [ "$(grep -c 'sha256:aaaabbbbccccdddd1111' "$FX/rmlog")" = 1 ]; then ok "duplicate image removed once"; else bad "duplicate image not removed exactly once"; fi
if grep -Eq '(^| )(-f|--force)( |$)|prune' "$FX/calls"; then bad "a forced or prune call was made"; else ok "never -f, never prune"; fi
if grep -Fq -- "--filter label=marvin.project=repo" "$FX/calls"; then ok "listing filtered by project label"; else bad "no project label filter"; fi

hd "D7 an image with several tags is kept, never untagged (a moved tag could name a foreign image)"
fx_D7 "$SWEEP"; assert_rc 0; assert_out 'kept: image "m:a" — D7 several tags — untag it by hand'; assert_no_rm sha256:9999aaaabbbbcccc
if [ -s "$FX/rmlog" ]; then bad "something was removed: $(tr '\n' ' ' < "$FX/rmlog")"; else ok "nothing removed"; fi

hd "R3 no image rm call ever receives a repo:tag — single-tag, untagged and multi-tag images alike"
fresh; orphans; img sha256:7777aaaabbbbcccc "k:a,k:b" repo gone throwaway; sweep "$SWEEP"; assert_rc 0
assert_out 'removed: image "app:t"'; assert_out 'kept: image "k:a" — D7'
bad_args=$(awk '$1 == "image" && $2 == "rm" && $NF !~ /^sha256:/' "$FX/calls")
if [ -z "$bad_args" ] && grep -q '^image rm' "$FX/calls"; then ok "image rm only ever by ID"; else bad "image rm by tag: $bad_args"; fi

hd "R2 a name with a space prints encoded"
fresh; ctr cs "my box" exited repo gone throwaway; sweep "$SWEEP"; assert_out 'removed: container "my box"'

hd "E1 an unreadable inspect or a multi-line label set is kept by name, never removed"
fresh; vol vbad repo gone throwaway; vol vnl repo gone throwaway; echo vbad > "$FX/inspectfail"; echo vnl > "$FX/inspectnl"
sweep "$SWEEP"; assert_rc 0; assert_out "kept: volume vbad — labels unreadable"; assert_out "kept: volume vnl — labels unreadable"
assert_no_rm vbad; assert_no_rm vnl

hd "E2 a listing that fails is reported; the other kinds still run"
fresh; orphans; : > "$FX/lsfail-network"; sweep "$SWEEP"; assert_rc 0
assert_out "kept: every network — listing unreadable"; assert_no_rm ngone; assert_rm cgone; assert_rm vgone

hd "E3 an option-looking listing entry is never passed on"
fresh; vol -f repo gone throwaway; sweep "$SWEEP"; assert_rc 0
if grep -Fq "inspect" "$FX/calls"; then bad "inspected an option-looking id"; else ok "skipped"; fi

hd "C1 --check reports and removes nothing"
fresh; orphans; sweep "$SWEEP" --check; assert_rc 0
assert_out "would remove: container cgname"; assert_out "would remove: volume vgone"; assert_no_out "removed: "
if [ -s "$FX/rmlog" ]; then bad "rm called under --check"; else ok "no rm logged"; fi

hd "H1 --hook prints the two summary lines exactly"
fresh; ctr cgone cgname exited repo gone throwaway; vol vgone repo gone throwaway; vol vm repo main throwaway
sweep "$SWEEP" --hook; assert_rc 0; assert_lines 2
assert_out "Marvin: removed 2 Docker resource(s) left by finished agent worktrees: cgname, vgone"
assert_out "Marvin: 1 throwaway Docker resource(s) owned by the main checkout remain — remove them once their task is done (.marvin/agents/tidying.md)"

hd "H2 --hook: the removed line only when N>0, the main-owned line only when K>0"
fresh; vol vm repo main throwaway; sweep "$SWEEP" --hook; assert_lines 1; assert_no_out "removed"; assert_out "owned by the main checkout remain"
fresh; vol vgone repo gone throwaway; sweep "$SWEEP" --hook; assert_lines 1; assert_out "Marvin: removed 1 Docker resource(s)"
fresh; vol v1 repo gone keep; sweep "$SWEEP" --hook; assert_rc 0; assert_empty

hd "H3 --hook does nothing outside a Marvin project"
fresh; orphans; rm -rf "$R/.marvin"; sweep "$SWEEP" --hook; assert_rc 0; assert_empty
if [ -s "$FX/calls" ]; then bad "docker was called"; else ok "docker never called"; fi

hd "N1 docker missing: --hook silent, plain mode one line, both exit 0"
fresh; OUT=$(cd "$R" && PATH="$SYS" DOCKER_FX="$FX" CLAUDE_PROJECT_DIR="$R" "$BASH" "$SWEEP" --hook </dev/null 2>&1); RC=$?
assert_rc 0; assert_empty
OUT=$(cd "$R" && PATH="$SYS" DOCKER_FX="$FX" CLAUDE_PROJECT_DIR="$R" "$BASH" "$SWEEP" </dev/null 2>&1); RC=$?
assert_rc 0; assert_out "docker: not available"; assert_lines 1

hd "N2 daemon unreachable: same as missing"
fresh; orphans; : > "$FX/down"; sweep "$SWEEP" --hook; assert_rc 0; assert_empty
sweep "$SWEEP"; assert_rc 0; assert_out "docker: not available"; assert_no_rm cgone

hd "U1 usage and not-a-repository"
sweep "$SWEEP" --bogus; assert_rc 2; assert_out "usage"
mkdir -p "$WORK/plain"
OUT=$(cd "$WORK/plain" && PATH="$FAKE:$PATH" DOCKER_FX="$FX" CLAUDE_PROJECT_DIR="$WORK/plain" "$BASH" "$SWEEP" </dev/null 2>&1); RC=$?
assert_rc 2; assert_out "not a git repository"
OUT=$(cd "$WORK/plain" && PATH="$FAKE:$PATH" DOCKER_FX="$FX" CLAUDE_PROJECT_DIR="$WORK/plain" "$BASH" "$SWEEP" --hook </dev/null 2>&1); RC=$?
assert_rc 0; assert_empty

# ── mutations: each reverts one guard in a copy; the guard's fixture must then fail ─────────────
mutation() {  # mutation <name> <fixture-fn> <check-fn> <exact script line> <replacement>
  local m="$WORK/mutant-$1.sh"
  A="$4" B="$5" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$SWEEP" > "$m"   # ENVIRON: no escape processing
  if cmp -s "$m" "$SWEEP"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  "$2" "$SWEEP"; if [ "$RC" != 0 ] || ! "$3"; then bad "mutation $1: fixture fails on the real script — harness is stale"; return; fi
  "$2" "$m"; if [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $RC)"; return; fi
  if "$3"; then bad "mutation $1 survived ($2 still passes)"; else ok "mutation $1 caught"; fi
}
hd "M mutations"
mutation D0 fx_D0 ck_D0 '  [ "$ck" = "$CK" ] || { keep "$kind" "$name" "D0 another checkout"; return; }' '  :'
mutation PROJ fx_PROJ ck_PROJ '  [ "$proj" = "$P" ] || return 0   # not ours, whatever the filter said: never listed, never touched' '  :'
mutation D1 fx_D1 ck_D1 '  [ "$life" = throwaway ] || { keep "$kind" "$name" "D1 lifetime keep"; return; }' '  :'
mutation D2 fx_D2 ck_D2 '  [ -z "$owner" ] || [ "$owner" = main ] && { keep "$kind" "$name" "D2 owned by the main checkout"; NMAIN=$((NMAIN + 1)); return; }' '  :'
mutation D3 fx_D3 ck_D3 '  owner_ok "$owner" || { keep "$kind" "$name" "D3 owner label invalid"; return; }' '  :'
mutation D3DOTS fx_D3 ck_D3 '  case "$o" in ""|.|..|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;; esac' \
                            '  case "$o" in ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;; esac'
mutation D4 fx_D4 ck_D4 '  [ -e "$WT_DIR/$owner" ] || [ -L "$WT_DIR/$owner" ] && { keep "$kind" "$name" "D4 owner worktree still present"; return; }' '  :'
mutation D4LINK fx_D4L ck_D4L '  [ -e "$WT_DIR/$owner" ] || [ -L "$WT_DIR/$owner" ] && { keep "$kind" "$name" "D4 owner worktree still present"; return; }' \
                              '  [ -e "$WT_DIR/$owner" ] && { keep "$kind" "$name" "D4 owner worktree still present"; return; }'
mutation D6 fx_D6 ck_D6 '  dk "$kind" rm -- "$id" >/dev/null 2>&1 || { keep "$kind" "$name" "D6 docker refused (in use)"; return; }' \
                        '  dk "$kind" rm -- "$id" >/dev/null 2>&1 || :'
mutation D7 fx_D7 ck_D7 '  case "$tags" in *,*) keep "$kind" "$name" "D7 several tags — untag it by hand"; return ;; esac' '  :'
mutation D5 fx_D5 ck_D5 '    case "$state" in exited|created|dead) ;; *) keep "$kind" "$name" "D5 container running"; return ;; esac' '    :'

printf '\n----\ntest-docker-sweep: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
