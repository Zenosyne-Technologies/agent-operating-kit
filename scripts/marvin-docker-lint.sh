#!/usr/bin/env bash
# marvin-docker-lint.sh — PreToolUse hook (matcher Bash) for the marvin plugin (v0.39.0).
# Advises — additionalContext, constant text, never a decision — when a Bash command run by the
# orchestrator OR a sub-agent:
#   - creates a Docker resource (docker run|create, docker container run|create, docker volume|network
#     create, docker build, docker builder|image|buildx build) with no `marvin.project` anywhere in it;
#   - starts a compose stack (docker compose / docker-compose … up|create|run) without a global
#     -p/--project-name (or a COMPOSE_PROJECT_NAME= assignment in front of it);
#   - runs/creates a mysql, percona or percona-server image (any registry, tag or digest) without
#     skip-log-bin, disable-log-bin, log-bin=OFF or log-bin=0 (case- and _/- insensitive) in the
#     command, or a mariadb image WITH --log-bin (not =OFF / =0) after the image.
# The rules it cites are owned by .marvin/agents/tidying.md.
# Detection: the command is split into shell words (quotes, backslash escapes, line continuations,
# comments) and simple commands (; & && | || ( ) ` and newlines); docker must sit in COMMAND POSITION,
# after any VAR=value assignments, redirections and the wrappers sudo, env, command, exec, time, nohup,
# nice (and their options). So `echo docker run x` and `echo "docker run x"` stay silent.
# Known limits: docker inside a quoted string run by another program (bash -c '…', ssh host '…'),
# through a variable/alias/function ($DOCKER run), via xargs/watch, or written with JSON \u escapes is
# not seen; heredoc bodies are read as commands; a mysql image run as a client (docker run mysql mysql
# -h …) still gets the binlog advice; `marvin.project` anywhere (even in an echo) suppresses the label
# advice; only the first 64 KiB of the command is parsed.
# Contract: Marvin projects only; fires for sub-agent calls too; never writes; always exits 0; nothing
# from the command is echoed.
set -u
[ -t 0 ] && exit 0
RAW=$(head -c 1048576 2>/dev/null) || exit 0
case "$RAW" in *docker*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
MH_IN=$RAW
[ "$(printf '%s' "$MH_IN" | mh_get tool_name)" = Bash ] || exit 0
cmd=$(printf '%s' "$MH_IN" | mh_get tool_input.command | head -c 65536) || exit 0
case "$cmd" in *docker*) ;; *) exit 0 ;; esac
root=$(mh_root); mh_is_marvin "$root" || exit 0

lc=$(printf '%s' "$cmd" | LC_ALL=C tr 'A-Z_' 'a-z-')
binoff=0
case "$lc" in *skip-log-bin*|*disable-log-bin*|*log-bin=off*|*log-bin=0*) binoff=1 ;; esac

IFS= read -r -d '' DL_AWK <<'AWK' || true
function flush() { if (inw) { tok[++nt] = w; w = ""; inw = 0 } }
function brk() { flush(); if (nt && tok[nt] != SEP) tok[++nt] = SEP }
function isredir(t) { return t ~ /^[0-9]*[<>]/ }
function bare(t) { return t ~ /^[0-9]*[<>]+&?$/ }
function wopt(wr, f) {
  if (wr == "sudo") return f ~ /^-[ughpCDrtUT]$/
  if (wr == "env") return f ~ /^-[uCSP]$/
  if (wr == "nice") return f == "-n"
  if (wr == "time") return f ~ /^-[fo]$/
  if (wr == "exec") return f == "-a"
  return 0 }
function nextarg(k, e) { while (k <= e && tok[k] ~ /^-/) k++; return k }
function lower(t) { t = tolower(t); gsub(/_/, "-", t); return t }
function runargs(s, e,   k, t, j, c, n) {
  res = 1
  for (k = s; k <= e; k++) {
    t = tok[k]
    if (isredir(t)) { if (bare(t)) k++; continue }
    if (t == "--") { k++; break }
    if (t ~ /^--/) {
      if (index(t, "=") || t ~ /^--(rm|init|privileged|read-only|detach|interactive|tty|publish-all|no-healthcheck|oom-kill-disable|disable-content-trust|use-api-socket|help|quiet)$/) continue
      k++; continue }
    if (t ~ /^-./) {
      for (j = 2; j <= length(t); j++) { c = substr(t, j, 1)
        if (index("acehlmpuvw", c)) { if (j == length(t)) k++; break } }
      continue }
    break }
  if (k > e) return
  n = tolower(tok[k]); sub(/@.*/, "", n); sub(/.*\//, "", n); sub(/:.*/, "", n)
  if (n == "mysql" || n == "percona" || n == "percona-server") { if (!binoff) db = 1; return }
  if (n != "mariadb") return
  for (j = k + 1; j <= e; j++) { t = lower(tok[j])
    if (t == "--log-bin" || (t ~ /^--log-bin=/ && t != "--log-bin=off" && t != "--log-bin=0")) db = 1 } }
function compose(s, e, cpn,   k, t, hasp) {
  hasp = cpn
  for (k = s; k <= e; k++) {
    t = tok[k]
    if (isredir(t)) { if (bare(t)) k++; continue }
    if (t == "-p" || t == "--project-name" || t ~ /^--project-name=/ || t ~ /^-p./) { hasp = 1; if (t == "-p" || t == "--project-name") k++; continue }
    if (t ~ /^-/) { if (t ~ /^(-f|--file|--profile|--env-file|--project-directory|--ansi|--progress|--parallel)$/) k++; continue }
    break }
  if (k <= e && (tok[k] == "up" || tok[k] == "create" || tok[k] == "run") && !hasp) cmp = 1 }
function segment(s, e,   k, t, b, wr, s1, s2, cpn) {
  k = s; cpn = 0
  while (k <= e) {
    t = tok[k]
    if (isredir(t)) { k += bare(t) ? 2 : 1; continue }
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { if (t ~ /^COMPOSE_PROJECT_NAME=./) cpn = 1; k++; continue }
    b = t; sub(/.*\//, "", b)
    if (b ~ /^(sudo|env|command|exec|time|nohup|nice)$/) {
      wr = b; k++
      while (k <= e && tok[k] ~ /^-/) { if (wopt(wr, tok[k])) k++; k++ }
      continue }
    break }
  if (k > e) return
  if (b == "docker-compose") { compose(k + 1, e, cpn); return }
  if (b != "docker") return
  for (k++; k <= e; k++) {
    t = tok[k]
    if (t ~ /^-/) { if (t ~ /^(-H|--host|-c|--context|--config|-l|--log-level|--tlscacert|--tlscert|--tlskey)$/) k++; continue }
    break }
  if (k > e) return
  s1 = tok[k]
  if (s1 == "run" || s1 == "create") { runargs(k + 1, e); return }
  if (s1 == "build") { res = 1; return }
  if (s1 == "compose") { compose(k + 1, e, cpn); return }
  k = nextarg(k + 1, e); if (k > e) return
  s2 = tok[k]
  if (s1 == "container" && (s2 == "run" || s2 == "create")) { runargs(k + 1, e); return }
  if ((s1 == "volume" || s1 == "network") && s2 == "create") res = 1
  if ((s1 == "image" || s1 == "buildx" || s1 == "builder") && s2 == "build") res = 1 }
BEGIN { SEP = "\001" }
{ L = length($0); cmt = 0; pc = ""
  for (o = 1; o <= L; o += 512) { chunk = substr($0, o, 512); cl = length(chunk)
    for (i = 1; i <= cl; i++) { c = substr(chunk, i, 1)
      if (cmt) break
      if (esc) { esc = 0; w = w c; inw = 1 }
      else if (q == 1) { if (c == "'") q = 0; else w = w c }
      else if (q == 2) { if (c == "\\") esc = 1; else if (c == "\"") q = 0; else w = w c }
      else if (c == "\\") { esc = 1; inw = 1 }
      else if (c == "'") { q = 1; inw = 1 }
      else if (c == "\"") { q = 2; inw = 1 }
      else if (c == " " || c == "\t" || c == "\r") flush()
      else if (c == "#" && !inw) cmt = 1
      else if (c == "&" && (pc == ">" || pc == "<")) { w = w c; inw = 1 }
      else if (index(";&|()`", c)) brk()
      else { w = w c; inw = 1 }
      pc = c }
    if (cmt) break }
  if (esc) { esc = 0; if (w == "") inw = 0 }
  else if (q) w = w " "
  else brk() }
END { flush()
  for (i = 1; i <= nt; i = j + 1) { for (j = i; j <= nt && tok[j] != SEP; j++); if (j > i) segment(i, j - 1) }
  printf "%s%s%s", (res ? "R" : ""), (cmp ? "C" : ""), (db ? "B" : "") }
AWK

hits=$(printf '%s\n' "$cmd" | LC_ALL=C awk -v binoff="$binoff" "$DL_AWK" 2>/dev/null) || exit 0
case "$cmd" in *marvin.project*) hits=${hits#R} ;; esac
[ -n "$hits" ] || exit 0

out="Marvin Docker lint (.marvin/agents/tidying.md):"
case "$hits" in *R*) out="$out this command creates a Docker resource without a marvin.project label — label every container, volume, network and image you create with marvin.project, marvin.checkout, marvin.owner and marvin.lifetime (Label every Docker resource you create)." ;; esac
case "$hits" in *C*) out="$out This command starts a compose stack without -p/--project-name — run it as -p <P>-<O> and declare the four labels on every service, volume and network in its compose file." ;; esac
case "$hits" in *B*) out="$out This command starts a MySQL/Percona/MariaDB container with binary logging on — a throwaway database runs with it off: MySQL/Percona --skip-log-bin (8.0+: --disable-log-bin too), MariaDB never --log-bin (Throwaway databases — binary logging off)." ;; esac
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$out"
exit 0
