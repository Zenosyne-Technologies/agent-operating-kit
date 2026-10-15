#!/usr/bin/env bash
# test-docker-lint.sh — behavioural tests for scripts/marvin-docker-lint.sh (PreToolUse Bash, v0.39.0).
# Pins: every resource-creating form gets the label advice unless marvin.project AND marvin.checkout
# (or --label-file) are in the command;
# compose up|create|run without a global -p/--project-name gets the compose advice; mysql/percona
# without a binlog-off flag and mariadb with --log-bin get the binlog advice; docker only in command
# position (echo docker run … stays silent); never a decision; no echo; sub-agent calls NOT skipped;
# non-Marvin and malformed input silent; never writes; exit 0. bash 3.2 + POSIX awk; python3 optional.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/marvin-docker-lint.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-dltest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
TF="$WORK.elapsed"   # outside $WORK, so D9's snapshot of $WORK sees only what the hook writes
trap 'rm -rf "$WORK" "$TF"' EXIT

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()   { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()   { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_no()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_empty() { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 160)"; fi; }
assert_json()  {  # python3 when present; else the hook lib's strict walker must read both keys back
  local v
  if command -v python3 >/dev/null 2>&1; then
    v=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])' 2>/dev/null)
  else
    v=$(. "$LIB"; printf '%s' "$OUT" | mh_get hookSpecificOutput.additionalContext >/dev/null && printf '%s' "$OUT" | mh_get hookSpecificOutput.hookEventName)
  fi
  if [ "$v" = PreToolUse ]; then ok "valid JSON"; else bad "not valid JSON"; fi
}

jstr() {  # JSON string literal of $1 (no python): escapes \ " tab, joins lines with \n
  printf '%s' "$1" | LC_ALL=C awk 'BEGIN { printf "\"" }
    { if (NR > 1) printf "\\n"; o = ""
      for (i = 1; i <= length($0); i++) { c = substr($0, i, 1)
        if (c == "\\") c = "\\\\"; else if (c == "\"") c = "\\\""; else if (c == "\t") c = "\\t"; o = o c }
      printf "%s", o }
    END { printf "\"" }'
}
P="$WORK/p"; mkdir -p "$P/.marvin"; printf -- '---\nkit_version: 0.39.0\n---\n' > "$P/.marvin/PROJECT-INFO.md"
pre_in() {  # pre_in <command> [prefix-fields] [tool]
  printf '{"session_id":"s"%s,"transcript_path":"%s/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":%s,"description":"d"}}' \
    "${2:-}" "$WORK" "$P" "${3:-Bash}" "$(jstr "$1")"
}
run() {  # run <project> <stdin> — sets OUT, RC and ELAPSED (seconds); HOOKX overrides the hook
  local TIMEFORMAT=%R
  { time OUT=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "${HOOKX:-$HOOK}" 2>&1); } 2>"$TF"
  RC=$?; ELAPSED=$(tail -n 1 "$TF")
}
fast() { awk -v t="$ELAPSED" 'BEGIN { exit !(t + 0 < 1) }'; }
LBL="without the marvin.project and marvin.checkout labels"; CMP="without -p/--project-name"; BIN="binary logging on"
lint() { run "$P" "$(pre_in "$1")"; }
fires()  { lint "$2"; if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "fires [$1]: $2"; else bad "silent [$1]: $2"; fi; [ "$RC" = 0 ] || bad "exit $RC: $2"; }
quiet()  { lint "$2"; if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "fired [$1]: $2"; else ok "no [$1]: $2"; fi; [ "$RC" = 0 ] || bad "exit $RC: $2"; }
silent() { lint "$1"; if [ -z "$OUT" ] && [ "$RC" = 0 ]; then ok "silent: $1"; else bad "not silent (exit $RC): $1"; fi; }

hd "D1 the fast path: no docker on stdin, nothing"
silent 'ls -la && git status'
silent 'podman run nginx'

hd "D2 every resource-creating form gets the label advice"
for c in 'docker run nginx' 'docker create nginx' 'docker container run nginx' 'docker container create nginx' \
  'docker volume create v1' 'docker network create n1' 'docker build -t x .' 'docker image build .' \
  'docker buildx build .' 'docker builder build .' 'docker --context ctx run nginx' 'docker -H tcp://h:2375 volume create v'; do
  fires "$LBL" "$c"; done
lint 'docker run nginx'; assert_json; assert_out '"hookEventName":"PreToolUse"'; assert_out "tidying.md"; assert_no "$CMP"; assert_no "$BIN"

hd "D3 command position survives env, sudo, wrappers, chains, continuations, substitutions"
for c in 'FOO=1 BAR=2 docker run nginx' 'sudo docker run nginx' 'sudo -u root -E docker run nginx' \
  'env A=b docker run nginx' 'nohup docker run nginx &' 'time docker run nginx' 'command docker run nginx' \
  'cd /x && docker run nginx' 'true; docker volume create v' 'false || docker network create n' \
  'tar c . | docker build -' 'x=$(docker create nginx)' 'echo `docker create nginx`' '(docker run nginx)' \
  '/usr/local/bin/docker run nginx' 'docker run nginx 2>&1 | tee log' "$(printf 'docker \\\n  run \\\n  nginx')" \
  "$(printf 'ls\ndocker run nginx')" '"docker" run nginx'; do
  fires "$LBL" "$c"; done

hd "D4 non-triggers stay silent"
for c in 'docker ps' 'docker ps -a' 'docker logs web' 'docker rm -f web' 'docker volume ls' 'docker volume rm v' \
  'docker network inspect n' 'docker image ls' 'docker images' 'docker exec web ls' 'docker stop web' \
  'docker volume create --label marvin.project=p --label marvin.checkout=/x v' 'docker run --label marvin.project=p --label marvin.checkout=/x --label marvin.owner=main nginx' \
  'docker build --label marvin.project=p --label marvin.checkout=/x .' 'echo docker run nginx' 'echo "docker run nginx"' "echo 'docker run nginx'" \
  'grep docker notes.txt' 'mydocker run nginx' 'docker-machine create m' '# docker run nginx' 'ls # docker run nginx' \
  'docker compose down -v' 'docker-compose down' 'docker compose ps' 'docker compose logs -f' 'docker' 'docker --help' \
  'docker volume' 'docker compose -p p up -d' 'docker compose --project-name p up' 'docker compose --project-name=p up' \
  'docker compose -pp up' 'COMPOSE_PROJECT_NAME=p docker compose up' 'docker-compose -p p up' 'docker container ls' \
  'docker run --help --label marvin.project=p --label marvin.checkout=/x'; do
  silent "$c"; done

hd "D5 compose up|create|run without a global -p"
for c in 'docker compose up' 'docker compose up -d' 'docker compose -f c.yml up -d' 'docker compose --profile x up' \
  'docker compose create' 'docker compose run web sh' 'docker compose run -p 8080:80 web' 'docker-compose up -d' \
  'docker-compose -f a.yml run web' 'sudo docker compose up' 'docker compose --file c.yml --env-file e up'; do
  fires "$CMP" "$c"; done
lint 'docker compose up'; assert_json; assert_no "$LBL"; assert_no "$BIN"
fires "$CMP" 'docker compose up -d && echo marvin.project'
quiet "$LBL" 'docker compose up'

hd "D6 mysql/percona without a binlog-off flag; mariadb with --log-bin"
for c in 'docker run mysql' 'docker run -d mysql:8.4' 'docker run docker.io/library/mysql:8.4' 'docker run mysql@sha256:abc' \
  'docker run -e MYSQL_ROOT_PASSWORD=x -p 3306:3306 --name db -d mysql:8' 'docker run -dit mysql' 'docker create percona' \
  'docker run percona/percona-server:8.0' 'docker container run --rm MySQL:8' 'docker run --network=n -v d:/var/lib/mysql mysql' \
  'docker run mariadb:11 --log-bin' 'docker run mariadb --log-bin=mysql-bin' 'docker run mariadb --log_bin' \
  'docker container create mariadb:10.11 --log-bin' 'docker run --label marvin.project=p --label marvin.checkout=/x mysql:8'; do
  fires "$BIN" "$c"; done
for c in 'docker run mysql:8 --skip-log-bin' 'docker run mysql:8 --disable-log-bin' 'docker run mysql:8 --log-bin=OFF' \
  'docker run mysql:8 --log_bin=OFF' 'docker run mysql:8 --log-bin=0' 'docker run mysql:8 --skip_log_bin' \
  'docker run mysql:8 --log-bin=off' 'docker run percona --skip-log-bin' 'docker run mariadb:11' \
  'docker run mariadb --log-bin=OFF' 'docker run mariadb --log-bin=0' 'docker run nginx' 'docker run -v mysql:/x nginx' \
  'docker run --network mysql nginx' 'docker run --name mysql nginx' 'docker run -e mysql nginx' 'docker run -h mysql nginx' 'docker volume create mysql' \
  'docker run mysqlrouter' 'docker run --log-bin mariadb'; do
  quiet "$BIN" "$c"; done
silent 'docker run --label marvin.project=p --label marvin.checkout=/x mysql:8.4 --skip-log-bin'
lint 'docker run --label marvin.project=p --label marvin.checkout=/x mysql:8'; assert_json; assert_no "$LBL"; assert_out "tidying.md"
lint 'docker compose up && docker run mysql'; assert_json; assert_out "$LBL"; assert_out "$CMP"; assert_out "$BIN"

hd "D7 never a decision, never a rewrite, never an echo"
lint 'docker run --name ZQXCANARY -e "Q=\"x\\" ZQXIMG/mysql:ZQXTAG'; assert_json; assert_out "$BIN"
assert_no "ZQX"; assert_no "permissionDecision"; assert_no "updatedInput"; assert_no '"decision"'
lint 'docker compose -f ZQXFILE.yml up'; assert_no "ZQX"

hd "D8 sub-agent calls fire too; other tools, non-Marvin projects, malformed stdin are silent"
run "$P" "$(pre_in 'docker run nginx' ',"agent_id":"a1","agent_type":"marvin:developer"')"; assert_rc0; assert_out "$LBL"
run "$P" "$(pre_in 'docker run nginx' '' Agent)"; assert_rc0; assert_empty
mkdir -p "$WORK/plain"; run "$WORK/plain" "$(pre_in 'docker run nginx')"; assert_rc0; assert_empty
ln -s "$P/.marvin" "$WORK/plain/.marvin"; run "$WORK/plain" "$(pre_in 'docker run nginx')"; assert_empty; rm -f "$WORK/plain/.marvin"
run "$P" '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"docker run nginx'; assert_rc0; assert_empty
run "$P" 'docker run nginx'; assert_rc0; assert_empty
run "$P" '{"tool_name":"Bash","tool_input":{}} docker'; assert_rc0; assert_empty

hd "D10 comments, exported compose names, label files"
silent 'ls # ; docker run nginx'
silent 'export COMPOSE_PROJECT_NAME=p; docker compose up'
silent 'export A=1 COMPOSE_PROJECT_NAME=p && docker compose up -d'
fires "$CMP" 'docker compose up; export COMPOSE_PROJECT_NAME=p'
fires "$CMP" 'export COMPOSE_PROJECT_NAME=; docker compose up'
fires "$CMP" 'export OTHER=p; docker compose up'
silent 'docker run --label-file labels.txt nginx'
silent 'docker build --label-file l.txt .'
silent 'docker volume create --label-file l.txt v'

hd "D11 Oracle MySQL images; client runs and entrypoint overrides get no binlog advice"
for c in 'docker run mysql/mysql-server:8.0' 'docker run container-registry.oracle.com/mysql/community-server:8.4' \
  'docker run mysql mysqld' 'docker run mysql:8 --character-set-server=utf8mb4'; do fires "$BIN" "$c"; done
for c in 'docker run --rm -v "$PWD":/w mysql:8.4 mysqldump -h db app' 'docker run -it mysql mysql -h db' \
  'docker run mysql:8 mysqladmin ping' 'docker run mysql mysqlimport x' 'docker run mysql mysqlsh' \
  'docker run mysql /usr/bin/mysql -h db' 'docker run mariadb:11 mariadb -h db --log-bin' 'docker run mariadb mariadb-dump x' \
  'docker run mariadb mariadb-admin ping --log-bin' 'docker run --entrypoint mysqladmin mysql:8 ping' \
  'docker run --entrypoint=sh mysql -c x' 'docker run foo/community-server' 'docker run bar/mysql-server' \
  'docker run mysql/mysql-server --skip-log-bin'; do quiet "$BIN" "$c"; done

hd "D12 a 60 KB word before a docker command finishes under 1 s"
LONGQ=$(head -c 60000 /dev/zero | tr '\0' q); LONGS=$(head -c 60000 /dev/zero | tr '\0' /)
lint "$LONGQ; docker ps"; if fast; then ok "60 KB slash-free word: ${ELAPSED}s"; else bad "60 KB slash-free word took ${ELAPSED}s"; fi
lint "$(printf 'cat > f <<EOF\n%s\nEOF\ndocker run --label marvin.project=p --label marvin.checkout=/x nginx' "$LONGQ")"; if fast; then ok "60 KB heredoc line: ${ELAPSED}s"; else bad "60 KB heredoc line took ${ELAPSED}s"; fi; assert_empty
lint "$LONGS; docker run nginx"; if fast; then ok "60 KB slash word: ${ELAPSED}s"; else bad "60 KB slash word took ${ELAPSED}s"; fi; assert_out "$LBL"

hd "D13 marvin.project alone is not enough — the sweep keeps resources without marvin.checkout"
fires "$LBL" 'docker run --label marvin.project=p nginx'
fires "$LBL" 'docker volume create --label marvin.project=p --label marvin.owner=main v'
fires "$LBL" 'docker run --label marvin.checkout=/x nginx'
silent 'docker run -l marvin.project=p -l marvin.checkout=/x -l marvin.owner=main -l marvin.lifetime=throwaway nginx'

hd "D9 never writes"
before=$(ls -laR "$WORK" | cksum); lint 'docker run mysql'
after=$(ls -laR "$WORK" | cksum); if [ "$before" = "$after" ]; then ok "nothing written"; else bad "the hook wrote something"; fi

check() {  # check <expect> — expect is "silent", "fast" (under 1 s), "has:<text>" or "no:<text>"
  case "$1" in
    silent) [ -z "$OUT" ] ;;
    fast) fast ;;
    has:*) printf '%s\n' "$OUT" | grep -Fq -- "${1#has:}" ;;
    no:*) ! printf '%s\n' "$OUT" | grep -Fq -- "${1#no:}" ;;
  esac
}
mutation() {  # mutation <name> <exact line> <replacement> <expect> <command> [prefix-fields]
  local d="$WORK/m-$1" in
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$LIB" "$d/lib/"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$d/hook.sh"   # ENVIRON: no escape processing
  if [ ! -f "$HOOK" ] || cmp -s "$d/hook.sh" "$HOOK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  in=$(pre_in "$5" "${6:-}")
  run "$P" "$in"; if [ "$RC" != 0 ] || ! check "$4"; then bad "mutation $1: fixture fails on the real hook — harness is stale"; return; fi
  HOOKX="$d/hook.sh" run "$P" "$in"
  if [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $RC)"; return; fi
  if check "$4"; then bad "mutation $1 survived ($4 still holds)"; else ok "mutation $1 caught"; fi
}
hd "M1 marvin.project suppression removed — D4 labelled run must catch it"
mutation label 'case "$cmd" in *marvin.project*) case "$cmd" in *marvin.checkout*) labelled=1 ;; esac ;; esac' ':' silent 'docker run --label marvin.project=p --label marvin.checkout=/x nginx'
hd "M1b marvin.checkout no longer required — D13 project alone must catch it"
mutation checkout 'case "$cmd" in *marvin.project*) case "$cmd" in *marvin.checkout*) labelled=1 ;; esac ;; esac' 'case "$cmd" in *marvin.project*) labelled=1 ;; esac' "has:$LBL" 'docker run --label marvin.project=p nginx'
hd "M2 binlog-off flags ignored — D6 --skip-log-bin must catch it"
mutation binoff 'case "$lc" in *skip-log-bin*|*disable-log-bin*|*log-bin=off*|*log-bin=0*) binoff=1 ;; esac' ':' "no:$BIN" 'docker run mysql:8 --skip-log-bin'
hd "M3 compose -p not recognised — D4 compose -p must catch it"
mutation composep '  if (k <= e && (tok[k] == "up" || tok[k] == "create" || tok[k] == "run") && !hasp) cmp = 1 }' '  if (k <= e && (tok[k] == "up" || tok[k] == "create" || tok[k] == "run")) cmp = 1 }' silent 'docker compose -p p up'
hd "M4 command position dropped (any docker word counts) — D4 echo must catch it"
mutation position '  if (b != "docker") return' '  if (b != "docker") { for (k = s; k <= e && tok[k] != "docker"; k++); if (k > e) return }' silent 'echo docker run nginx'
hd "M5 short option values not skipped — D6 -h mysql must catch it"
mutation optval '        if (index("acehlmpuvw", c)) { if (j == length(t)) k++; break } }' '        if (0) break }' silent 'docker run -h mysql nginx --label marvin.project=p --label marvin.checkout=/x'
hd "M6 mariadb --log-bin check removed — D6 mariadb --log-bin must catch it"
mutation mariadb '    if (t == "--log-bin" || (t ~ /^--log-bin=/ && t != "--log-bin=off" && t != "--log-bin=0")) db = 1 } }' '    } }' "has:$BIN" 'docker run --label marvin.project=p --label marvin.checkout=/x mariadb --log-bin'
hd "M7 sub-agent calls skipped — D8 must catch it"
mutation subagent 'MH_IN=$RAW' 'MH_IN=$RAW; mh_is_subagent_call && exit 0' "has:$LBL" 'docker run nginx' ',"agent_id":"a1"'

hd "M8 --label-file not counted — D10 must catch it"
mutation labelfile 'case "$cmd" in *--label-file*) labelled=1 ;; esac' ':' silent 'docker run --label-file l.txt nginx'
hd "M9 basename strip dropped — D3 /usr/local/bin/docker must catch it"
mutation base '  while ((i = index(t, "/")) > 0) t = substr(t, i + 1)' '  i = 0' "has:$LBL" '/usr/local/bin/docker run nginx'
hd "M11 Oracle MySQL images dropped — D11 mysql/mysql-server must catch it"
mutation oracle '  if ((n == "mysql-server" || n == "community-server") && img ~ /(^|\/)mysql\/$/) { if (!binoff) db = 1; return }' '' "has:$BIN" 'docker run mysql/mysql-server:8.0'
hd "M12 client runs not recognised — D11 mysqldump must catch it"
mutation client '  if (ep || (k < e && client(base(tok[k + 1])))) return' '  if (ep) return' "no:$BIN" 'docker run mysql:8.4 mysqldump -h db app'
hd "M13 --entrypoint not recognised — D11 must catch it"
mutation entrypoint '      if (t ~ /^--entrypoint(=|$)/) ep = 1' '' "no:$BIN" 'docker run --entrypoint mysqladmin mysql:8 ping'
hd "M14 exported COMPOSE_PROJECT_NAME ignored — D10 must catch it"
mutation export '  if (gcpn) cpn = 1' '' silent 'export COMPOSE_PROJECT_NAME=p; docker compose up'
hd "M15 comment handling dropped — D10 ls # ; docker run must catch it"
mutation comment '      else if (c == "#" && !inw) cmt = 1' '      else if (0) cmt = 1' silent 'ls # ; docker run nginx'

printf '\n----\ntest-docker-lint: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
