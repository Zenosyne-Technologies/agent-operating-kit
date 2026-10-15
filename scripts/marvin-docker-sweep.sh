#!/usr/bin/env bash
# marvin-docker-sweep.sh — remove throwaway Docker resources of finished agent worktrees (AOS-216, v0.39.0).
#
#   marvin-docker-sweep.sh [--check] [--hook] [<repo-dir>]      repo-dir: $CLAUDE_PROJECT_DIR, else $PWD
#
# Scope: containers, networks, volumes and images labelled marvin.project=<P> exactly, P being the
# main checkout's directory name (the first `git worktree list` entry, C). Listed by label filter,
# then each one's labels are read again by `docker <kind> inspect` and the project label re-checked
# before anything is done to it. A resource is KEPT when any guard holds:
#   D0 marvin.checkout is absent or differs from C byte for byte (another checkout with the same name)
#   D1 marvin.lifetime is not throwaway
#   D2 marvin.owner is main or empty (the orchestrator removes those when their task closes)
#   D3 marvin.owner fails ^[A-Za-z0-9._-]+$ or is . / ..
#   D4 <main checkout>/.claude/worktrees/<owner> exists (any type, a symlink included)
#   D5 a container's state is not exited, created or dead
#   D6 docker refused the removal (in use)
# Otherwise: docker rm / network rm / volume rm / image rm, in that order — never -f, never prune.
# An image with several tags is untagged tag by tag (image rm <repo:tag>), then removed by its ID.
# Rules: .marvin/agents/tidying.md. Names print through q() (git core.quotePath convention).
# --check reports only. --hook (SessionStart): Marvin projects only, at most two summary lines,
# otherwise silent, always exit 0. Docker missing or its daemon unreachable: --hook silent, else
# one line `docker: not available`; both exit 0.
# Exit without --hook: 0 ok · 2 usage / not a git repository.
set -u

MODE=run; HOOK=0; REPO=""; NREM=0; REMOVED=""; NMAIN=0
USAGE="usage: marvin-docker-sweep.sh [--check] [--hook] [<repo-dir>]"
NL='
'
TAB='	'

q() {
  # LC_ALL=C for the classification too: bash range expressions follow locale collation. The
  # set is enumerated rather than ranged, so collation cannot reorder it either.
  local p="$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C
  case "$p" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*) ;;
    *) printf '%s' "$p"; return 0;;
  esac
  printf '%s' "$p" | LC_ALL=C od -An -v -tu1 | awk '
    BEGIN{ printf "\"" }
    { for(i=1;i<=NF;i++){ b=$i+0
        if(b==92) printf "\\\\"
        else if(b==34) printf "\\\""
        else if(b==10) printf "\\n"
        else if(b==9)  printf "\\t"
        else if(b==13) printf "\\r"
        else if(b<32 || b>126) printf "\\%03o", b
        else printf "%c", b } }
    END{ printf "\"" }'
}
say()  { [ "$HOOK" = 1 ] || printf '%s\n' "$1"; }
keep() { say "kept: $1 $(q "$2") — $3"; }
die()  { [ "$HOOK" = 1 ] && exit 0; printf 'marvin-docker-sweep: %s\n' "$2" >&2; exit "$1"; }

for a in "$@"; do case "$a" in --hook) HOOK=1 ;; esac; done
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --hook)  ;;
    -*)      die 2 "$USAGE" ;;
    *)       [ -z "$REPO" ] || die 2 "$USAGE"; REPO="$a" ;;
  esac
done

REPO=${REPO:-${CLAUDE_PROJECT_DIR:-$PWD}}
common=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die 2 "not a git repository: $(q "$REPO")"
case "$common" in */.git) ROOT=${common%/.git} ;; *) die 2 "no main checkout (bare repository or separate git dir)" ;; esac
if [ "$HOOK" = 1 ]; then [ -d "$ROOT/.marvin" ] && [ ! -L "$ROOT/.marvin" ] || exit 0; fi
CK=$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$CK" ] || die 2 "no main checkout listed by git worktree list"
P=$(basename "$CK")
WT_DIR="$ROOT/.claude/worktrees"

TMO=""; command -v timeout >/dev/null 2>&1 && TMO=8   # bound each call; else the hook timeout bounds us
dk() { if [ -n "$TMO" ]; then timeout "$TMO" docker "$@" </dev/null; else docker "$@" </dev/null; fi; }

if ! command -v docker >/dev/null 2>&1 || ! dk info >/dev/null 2>&1; then
  say "docker: not available"; exit 0
fi

owner_ok() {  # owner_ok <owner> — ^[A-Za-z0-9._-]+$ and not . or ..
  local o="$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C
  case "$o" in ""|.|..|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 1 ;; esac
  return 0
}

# inspect formats: one tab-separated line — name [state] project checkout owner lifetime
LBL='{{index .Labels "marvin.project"}}{{"\t"}}{{index .Labels "marvin.checkout"}}{{"\t"}}{{index .Labels "marvin.owner"}}{{"\t"}}{{index .Labels "marvin.lifetime"}}'
CLBL='{{index .Config.Labels "marvin.project"}}{{"\t"}}{{index .Config.Labels "marvin.checkout"}}{{"\t"}}{{index .Config.Labels "marvin.owner"}}{{"\t"}}{{index .Config.Labels "marvin.lifetime"}}'
F_container='{{.Name}}{{"\t"}}{{.State.Status}}{{"\t"}}'"$CLBL"
F_network='{{.Name}}{{"\t"}}'"$LBL"
F_volume='{{.Name}}{{"\t"}}'"$LBL"
F_image='{{join .RepoTags ","}}{{"\t"}}'"$CLBL"

list() {  # list <kind> — IDs (volume names) carrying the project label, de-duplicated
  local fmt='{{.ID}}'
  case "$1" in
    container) dk container ls -a --no-trunc --filter "label=marvin.project=$P" --format "$fmt" ;;
    network)   dk network ls --no-trunc --filter "label=marvin.project=$P" --format "$fmt" ;;
    volume)    dk volume ls --filter "label=marvin.project=$P" --format '{{.Name}}' ;;
    image)     dk image ls --no-trunc --filter "label=marvin.project=$P" --format "$fmt" ;;
  esac
}

consider() {  # consider <kind> <id>
  local kind="$1" id="$2" fmt out name state="" proj ck owner life tags="" rest t
  eval "fmt=\$F_$kind"
  out=$(dk "$kind" inspect --format "$fmt" -- "$id" 2>/dev/null) || { keep "$kind" "$id" "labels unreadable"; return; }
  case "$out" in *"$NL"*) keep "$kind" "$id" "labels unreadable"; return ;; esac
  name=${out%%"$TAB"*}; out=${out#*"$TAB"}
  if [ "$kind" = container ]; then state=${out%%"$TAB"*}; out=${out#*"$TAB"}; name=${name#/}; fi
  proj=${out%%"$TAB"*}; out=${out#*"$TAB"}
  ck=${out%%"$TAB"*}; out=${out#*"$TAB"}
  owner=${out%%"$TAB"*}; life=${out#*"$TAB"}
  [ "$kind" = image ] && { tags=$name; name=${tags%%,*}; }   # every repo:tag, comma-joined
  [ -n "$name" ] || { name=${id#sha256:}; [ "${#name}" -gt 12 ] && name=${name%"${name#????????????}"}; }   # untagged image: short ID
  [ "$proj" = "$P" ] || return 0   # not ours, whatever the filter said: never listed, never touched
  [ "$ck" = "$CK" ] || { keep "$kind" "$name" "D0 another checkout"; return; }
  [ "$life" = throwaway ] || { keep "$kind" "$name" "D1 lifetime keep"; return; }
  [ -z "$owner" ] || [ "$owner" = main ] && { keep "$kind" "$name" "D2 owned by the main checkout"; NMAIN=$((NMAIN + 1)); return; }
  owner_ok "$owner" || { keep "$kind" "$name" "D3 owner label invalid"; return; }
  [ -e "$WT_DIR/$owner" ] || [ -L "$WT_DIR/$owner" ] && { keep "$kind" "$name" "D4 owner worktree still present"; return; }
  if [ "$kind" = container ]; then
    case "$state" in exited|created|dead) ;; *) keep "$kind" "$name" "D5 container running"; return ;; esac
  fi
  if [ "$MODE" = check ]; then say "would remove: $kind $(q "$name")"; return 0; fi
  rest=$tags   # several tags: untag all but the last; removing the ID then drops the image
  while :; do
    case "$rest" in *,*) t=${rest%%,*}; rest=${rest#*,} ;; *) break ;; esac
    dk image rm -- "$t" >/dev/null 2>&1 || { keep "$kind" "$name" "D6 docker refused (in use)"; return; }
  done
  dk "$kind" rm -- "$id" >/dev/null 2>&1 || { keep "$kind" "$name" "D6 docker refused (in use)"; return; }
  say "removed: $kind $(q "$name")"
  NREM=$((NREM + 1)); REMOVED="$REMOVED${REMOVED:+,} $(q "$name")"
}

for kind in container network volume image; do   # removal order: what uses a thing goes first
  ids=$(list "$kind" 2>/dev/null) || { say "kept: every $kind — listing unreadable"; continue; }
  ids=$(printf '%s\n' "$ids" | awk 'NF && !seen[$0]++')
  [ -n "$ids" ] || continue
  while IFS= read -r id; do
    case "$id" in -*|*[[:space:]]*) continue ;; esac   # never an option, never a split word
    consider "$kind" "$id"
  done <<EOF
$ids
EOF
done

if [ "$HOOK" = 1 ]; then
  [ "$NREM" -gt 0 ] && printf 'Marvin: removed %d Docker resource(s) left by finished agent worktrees:%s\n' "$NREM" "$REMOVED"
  [ "$NMAIN" -gt 0 ] && printf 'Marvin: %d throwaway Docker resource(s) owned by the main checkout remain — remove them once their task is done (.marvin/agents/tidying.md)\n' "$NMAIN"
fi
exit 0
