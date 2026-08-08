#!/usr/bin/env bash
# test_trust_guard.sh — v1.5.6-alpha: ⚙️ affect prosthetic #1.
# Isolates via STATE_DIR env var + tmp transcript files.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HOOKS_DIR/trust-guard.sh"

[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT not executable"; exit 1; }

PASS=0
FAIL=0

assert_fires() {
    local label="$1" input="$2" transcript="$3"
    local out
    out=$(printf '%s' "$input" | TRANSCRIPT_PATH_OVERRIDE="$transcript" STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
    if echo "$out" | grep -q 'Trust-guard'; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: expected marker, got: $out"
    fi
}

assert_silent() {
    local label="$1" input="$2" transcript="$3"
    local out
    out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
    if [ -z "$out" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [$label]: expected silent, got: $out"
    fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

# --- Empty transcript fixture ---
EMPTY="$TMP/empty.jsonl"
: > "$EMPTY"

# --- Transcript with auth for /tmp/foo ---
AUTH_FOO="$TMP/auth-foo.jsonl"
cat > "$AUTH_FOO" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"удали /tmp/foo пожалуйста"}]}}
EOF

# --- Transcript without auth ---
NO_AUTH="$TMP/no-auth.jsonl"
cat > "$NO_AUTH" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"что у нас в папке"}]}}
EOF

# --- Transcript with tool_result noise + no text auth ---
NOISE="$TMP/noise.jsonl"
cat > "$NOISE" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t1","type":"tool_result","content":"rm -rf /tmp/foo executed"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"давай дальше"}]}}
EOF

# --- Transcript with force-push auth on main ---
AUTH_PUSH="$TMP/auth-push.jsonl"
cat > "$AUTH_PUSH" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"force push main please, затри всё"}]}}
EOF

# --- Transcript with generic consent ---
AUTH_GENERIC="$TMP/auth-generic.jsonl"
cat > "$AUTH_GENERIC" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"да, снеси всё что не нужно"}]}}
EOF

# ----------------------------------------------------------------------
# Positive detection (marker fires)
# ----------------------------------------------------------------------

# T1: rm -rf without auth
input='{"session_id":"t1","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/bar"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'rm -rf' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T1 rm -rf no auth]: $out"; }

# T2: rm -rf message contains target — auth granted, silent
STATE_DIR="$TMP/state-t2"
mkdir -p "$STATE_DIR"
input='{"session_id":"t2","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"},"transcript_path":"'$AUTH_FOO'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T2 auth for /tmp/foo]: $out"; }

# T3: auth for /tmp/foo but command targets /tmp/other → marker fires (target mismatch)
STATE_DIR="$TMP/state-t3"
mkdir -p "$STATE_DIR"
input='{"session_id":"t3","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/other"},"transcript_path":"'$AUTH_FOO'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'Trust-guard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T3 auth for /tmp/foo but rm /tmp/other]: $out"; }

# T4: git reset --hard without auth
STATE_DIR="$TMP/state-t4"
mkdir -p "$STATE_DIR"
input='{"session_id":"t4","tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~3"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git reset --hard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T4 git reset --hard]: $out"; }

# T5: git push --force without auth
STATE_DIR="$TMP/state-t5"
mkdir -p "$STATE_DIR"
input='{"session_id":"t5","tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git push --force' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T5 git push --force]: $out"; }

# T6: git push --force WITH explicit auth on main
STATE_DIR="$TMP/state-t6"
mkdir -p "$STATE_DIR"
input='{"session_id":"t6","tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"transcript_path":"'$AUTH_PUSH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T6 force-push auth on main]: $out"; }

# T7: git branch -D without auth
STATE_DIR="$TMP/state-t7"
mkdir -p "$STATE_DIR"
input='{"session_id":"t7","tool_name":"Bash","tool_input":{"command":"git branch -D feature/foo"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git branch -D' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T7 git branch -D]: $out"; }

# T8: git checkout -- without auth
STATE_DIR="$TMP/state-t8"
mkdir -p "$STATE_DIR"
input='{"session_id":"t8","tool_name":"Bash","tool_input":{"command":"git checkout -- src/main.ts"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git checkout' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T8 git checkout --]: $out"; }

# T9: git clean -fd without auth
STATE_DIR="$TMP/state-t9"
mkdir -p "$STATE_DIR"
input='{"session_id":"t9","tool_name":"Bash","tool_input":{"command":"git clean -fd"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git clean' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T9 git clean -fd]: $out"; }

# T10: per-session throttle — second call with same signature+target silent
STATE_DIR="$TMP/state-t10"
mkdir -p "$STATE_DIR"
input='{"session_id":"t10","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/bar"},"transcript_path":"'$NO_AUTH'"}'
out1=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
out2=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
if echo "$out1" | grep -q 'Trust-guard' && [ -z "$out2" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T10 throttle]: out1='$out1' out2='$out2'"
fi

# T11: different session_id → NOT throttled
STATE_DIR="$TMP/state-t11"
mkdir -p "$STATE_DIR"
input1='{"session_id":"t11a","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"transcript_path":"'$NO_AUTH'"}'
input2='{"session_id":"t11b","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"transcript_path":"'$NO_AUTH'"}'
out1=$(printf '%s' "$input1" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
out2=$(printf '%s' "$input2" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
if echo "$out1" | grep -q 'Trust-guard' && echo "$out2" | grep -q 'Trust-guard'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T11 cross-session]: out1='$out1' out2='$out2'"
fi

# T12: generic consent («да, снеси всё») without target — auth granted
STATE_DIR="$TMP/state-t12"
mkdir -p "$STATE_DIR"
input='{"session_id":"t12","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/random"},"transcript_path":"'$AUTH_GENERIC'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T12 generic consent]: $out"; }

# ----------------------------------------------------------------------
# Negative detection (silent)
# ----------------------------------------------------------------------

# T13: non-destructive command (ls) → silent
STATE_DIR="$TMP/state-t13"
mkdir -p "$STATE_DIR"
input='{"session_id":"t13","tool_name":"Bash","tool_input":{"command":"ls -la /tmp"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T13 ls silent]: $out"; }

# T14: rm without -rf → silent (not destructive enough)
STATE_DIR="$TMP/state-t14"
mkdir -p "$STATE_DIR"
input='{"session_id":"t14","tool_name":"Bash","tool_input":{"command":"rm /tmp/a.txt"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T14 rm without -rf]: $out"; }

# T15: git push without --force → silent
STATE_DIR="$TMP/state-t15"
mkdir -p "$STATE_DIR"
input='{"session_id":"t15","tool_name":"Bash","tool_input":{"command":"git push origin main"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T15 git push silent]: $out"; }

# T16: non-Bash tool → silent
STATE_DIR="$TMP/state-t16"
mkdir -p "$STATE_DIR"
input='{"session_id":"t16","tool_name":"Edit","tool_input":{"command":"rm -rf /tmp/foo"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T16 non-Bash tool silent]: $out"; }

# T17: empty input → silent
STATE_DIR="$TMP/state-t17"
mkdir -p "$STATE_DIR"
out=$(printf '' | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T17 empty input]: $out"; }

# T18: tool_result noise in transcript doesn't grant auth (rm -rf /tmp/foo in tool_result, no text auth)
STATE_DIR="$TMP/state-t18"
mkdir -p "$STATE_DIR"
input='{"session_id":"t18","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/foo"},"transcript_path":"'$NOISE'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'Trust-guard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T18 tool_result noise != auth]: $out"; }

# ----------------------------------------------------------------------
# Edge cases
# ----------------------------------------------------------------------

# T19: rm -fr variant
STATE_DIR="$TMP/state-t19"
mkdir -p "$STATE_DIR"
input='{"session_id":"t19","tool_name":"Bash","tool_input":{"command":"rm -fr /tmp/quux"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'rm -rf' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T19 rm -fr variant]: $out"; }

# T20: rm -Rf variant
STATE_DIR="$TMP/state-t20"
mkdir -p "$STATE_DIR"
input='{"session_id":"t20","tool_name":"Bash","tool_input":{"command":"rm -Rf /tmp/quux"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'rm -rf' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T20 rm -Rf variant]: $out"; }

# T21: git push -f (short form)
STATE_DIR="$TMP/state-t21"
mkdir -p "$STATE_DIR"
input='{"session_id":"t21","tool_name":"Bash","tool_input":{"command":"git push -f origin main"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'git push --force' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T21 git push -f short]: $out"; }

# T22: destructive after semicolon in composite command
STATE_DIR="$TMP/state-t22"
mkdir -p "$STATE_DIR"
input='{"session_id":"t22","tool_name":"Bash","tool_input":{"command":"cd /tmp && rm -rf cache"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'Trust-guard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T22 composite command]: $out"; }

# T23: different target same signature — throttle by (signature+target), separate hash
STATE_DIR="$TMP/state-t23"
mkdir -p "$STATE_DIR"
input1='{"session_id":"t23","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/a"},"transcript_path":"'$NO_AUTH'"}'
input2='{"session_id":"t23","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/b"},"transcript_path":"'$NO_AUTH'"}'
out1=$(printf '%s' "$input1" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
out2=$(printf '%s' "$input2" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
if echo "$out1" | grep -q '/tmp/a' && echo "$out2" | grep -q '/tmp/b'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T23 different targets not throttled]: out1='$out1' out2='$out2'"
fi

# T24: reset --hard with auth «сброс» on implicit HEAD
STATE_DIR="$TMP/state-t24"
mkdir -p "$STATE_DIR"
AUTH_RESET="$TMP/auth-reset.jsonl"
cat > "$AUTH_RESET" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"сделай reset hard, надо сбросить всё"}]}}
EOF
input='{"session_id":"t24","tool_name":"Bash","tool_input":{"command":"git reset --hard"},"transcript_path":"'$AUTH_RESET'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T24 implicit HEAD auth reset hard]: $out"; }

# T25: missing transcript_path → still fires marker (safe default — no auth)
STATE_DIR="$TMP/state-t25"
mkdir -p "$STATE_DIR"
input='{"session_id":"t25","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/no-transcript"}}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'Trust-guard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T25 missing transcript]: $out"; }

# T26: silent marker is properly JSON with hookSpecificOutput
STATE_DIR="$TMP/state-t26"
mkdir -p "$STATE_DIR"
input='{"session_id":"t26","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/json"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
event=$(echo "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
ctx=$(echo "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
if [ "$event" = "PreToolUse" ] && echo "$ctx" | grep -q 'Trust-guard'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T26 JSON shape]: event='$event' ctx-head='${ctx:0:80}'"
fi

# T27: marker mentions affect prosthetic principle reference
STATE_DIR="$TMP/state-t27"
mkdir -p "$STATE_DIR"
input='{"session_id":"t27","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/principle"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'affect-as-engineering' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T27 principle ref]: $out"; }

# T28: auth for force-push on wrong branch → marker fires
STATE_DIR="$TMP/state-t28"
mkdir -p "$STATE_DIR"
# auth mentions "main" but command force-pushes "prod" — mismatch
input='{"session_id":"t28","tool_name":"Bash","tool_input":{"command":"git push --force origin prod"},"transcript_path":"'$AUTH_PUSH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
# AUTH_PUSH says "force push main please, затри всё" — "затри" is auth token,
# generic-consent match fires because "да," check doesn't apply, but
# implicit force-push consent is the action-verb rule. Expected fire
# because target prod mismatches "main" AND no generic "да," phrase.
# Note: our rule allows auth for implicit targets (HEAD/remote/working_tree)
# if action verb matches. For explicit target prod, we require basename match.
echo "$out" | grep -q 'git push --force' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T28 force-push target mismatch]: $out"; }

# T29: empty COMMAND → silent
STATE_DIR="$TMP/state-t29"
mkdir -p "$STATE_DIR"
input='{"session_id":"t29","tool_name":"Bash","tool_input":{"command":""},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
[ -z "$out" ] && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T29 empty command]: $out"; }

# T30: destructive-path rm (rm -f /important even without -rf)
STATE_DIR="$TMP/state-t30"
mkdir -p "$STATE_DIR"
input='{"session_id":"t30","tool_name":"Bash","tool_input":{"command":"rm -f /etc/passwd"},"transcript_path":"'$NO_AUTH'"}'
out=$(printf '%s' "$input" | STATE_DIR="$STATE_DIR" bash "$SCRIPT" 2>/dev/null)
echo "$out" | grep -q 'Trust-guard' && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); echo "FAIL [T30 rm destructive path]: $out"; }

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "OK: trust-guard $PASS/$TOTAL passed"
    exit 0
else
    echo "FAIL: trust-guard $PASS/$TOTAL passed, $FAIL failed"
    exit 1
fi
