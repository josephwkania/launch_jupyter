#!/bin/bash
# Tests for launch_jupyter that need no Slurm cluster: fake sbatch, squeue,
# scontrol and jupyter-lab commands stand in for the real ones.
#
# Run from the repo root:  bash tests/run_tests.sh

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
# Run a copy, so a local site config.sh next to the real script is not used.
SCRIPT="${WORK}/launch_jupyter"
cp "${ROOT}/launch_jupyter" "${SCRIPT}"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; echo "----- output -----"; echo "$2"; echo "------------------"; FAIL=$((FAIL + 1)); }

# check <name> <test expression...>   e.g. check "exits 0" "$rc" -eq 0
check() {
    local name="$1"; shift
    if [ "$@" ]; then pass "${name}"; else fail "${name}" "${out:-}"; fi
}

# expect <name> <substring> <output>
expect() {
    if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (missing: $2)" "$3"; fi
}

# --------------------------------------------------------------------------
# Fake Slurm and Jupyter
# --------------------------------------------------------------------------

FAKE="${WORK}/bin"
mkdir -p "${FAKE}"
export FAKE_STATE="${WORK}/state"
mkdir -p "${FAKE_STATE}"

# sbatch: records its arguments, writes the log the scenario asks for
# (FAKE_LOG_CONTENT) to the --output path, and prints a job ID.
cat >"${FAKE}/sbatch" <<'EOF'
#!/bin/bash
echo "$@" >"${FAKE_STATE}/sbatch_args"
out=""
for a in "$@"; do
    case "$a" in --output=*) out="${a#--output=}" ;; esac
done
if [[ -n "${FAKE_SBATCH_FAIL:-}" ]]; then
    echo "sbatch: error: Invalid partition name specified" >&2
    exit 1
fi
log="${out//%j/12345}"
[[ -n "$out" ]] && printf '%b' "${FAKE_LOG_CONTENT:-}" >"$log"
echo "12345;cluster"
EOF

# squeue: the end-time query (-o %e) gets FAKE_END; anything else gets
# whatever the scenario sets in FAKE_SQUEUE.
cat >"${FAKE}/squeue" <<'EOF'
#!/bin/bash
if [[ " $* " == *" %e "* ]]; then
    [[ -n "${FAKE_END:-}" ]] && echo "${FAKE_END}"
    exit 0
fi
[[ -n "${FAKE_SQUEUE:-}" ]] && printf '%b\n' "${FAKE_SQUEUE}"
exit 0
EOF

# scontrol: reports the job's StdOut path.
cat >"${FAKE}/scontrol" <<'EOF'
#!/bin/bash
echo "JobId=12345 JobName=jupyter StdOut=${FAKE_STDOUT:-} Command=${FAKE_COMMAND:-}"
EOF

# jupyter-lab: records its arguments and prints a URL like Jupyter does.
cat >"${FAKE}/jupyter-lab" <<'EOF'
#!/bin/bash
echo "$@" >"${FAKE_STATE}/jupyter_args"
port=""
for a in "$@"; do case "$a" in --port=*) port="${a#--port=}" ;; esac; done
echo "[I ServerApp] http://127.0.0.1:${port}/lab?token=abc123def456"
EOF

scancel_log="${FAKE_STATE}/scancel"
cat >"${FAKE}/scancel" <<EOF
#!/bin/bash
echo "\$@" >>"${scancel_log}"
EOF

chmod +x "${FAKE}"/*
export PATH="${FAKE}:${PATH}"

# Isolate from any real config.
export HOME="${WORK}/home"
mkdir -p "${HOME}"
export LJ_LOG_DIR="${WORK}/logs"
unset LAUNCH_JUPYTER_CONFIG XDG_CONFIG_HOME XDG_STATE_HOME SLURM_JOB_ID 2>/dev/null || true

LOG="${LJ_LOG_DIR}/jupyter-12345.log"

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

echo "== basic options"
out=$("${SCRIPT}" --help 2>&1); rc=$?
check "--help exits 0" "$rc" -eq 0
expect "--help shows usage" "Usage: launch_jupyter" "$out"
expect "--help lists --vscode" "--vscode" "$out"

# shellcheck disable=SC2088  # a literal ~ is what the help should show
expect "--help shows the user config path, not a variable" "~/.config/launch_jupyter/config.sh" "$out"
# shellcheck disable=SC2016  # looking for a literal ${ in the output
if [[ "$out" != *'${'* ]]; then pass "--help has no unexpanded variables"
else fail "--help shows a raw variable" "$out"; fi

out=$("${SCRIPT}" -V 2>&1)
expect "-V prints version" "launch_jupyter " "$out"

out=$("${SCRIPT}" --no-such-option 2>&1); rc=$?
check "unknown option exits non-zero" "$rc" -ne 0
expect "unknown option is an error" "unknown option '--no-such-option' (see launch_jupyter --help)" "$out"
if [[ "$out" != *"Usage:"* ]]; then pass "unknown option does not dump the whole help"
else fail "unknown option printed the full help" "$out"; fi

out=$("${SCRIPT}" -c 2>&1); rc=$?
check "missing value exits non-zero" "$rc" -ne 0
expect "missing value is explained" "-c needs a value, e.g. -c 8" "$out"
out=$("${SCRIPT}" -m -t 1:00:00 2>&1)
expect "an option is not taken as a value" "-m needs a value, e.g. -m 32G" "$out"
if [[ ! -e "${FAKE_STATE}/sbatch_args" ]]; then pass "bad options submit nothing"
else fail "a job was submitted despite bad options" "$(cat "${FAKE_STATE}/sbatch_args")"; fi

echo "== launcher: Jupyter"
export FAKE_LOG_CONTENT="  ssh -J me@login.example.org me@node001 -L 8888:127.0.0.1:8888 -N\n[I ServerApp] http://127.0.0.1:8888/lab?token=0123abcd\n"
export FAKE_SQUEUE="RUNNING|None"
out=$(FAKE_END=2026-11-18T23:15:42 "${SCRIPT}" -c 2 -m 4G -t 1:00:00 -p testpart 2>&1); rc=$?
check "launcher exits 0 when Jupyter is ready" "$rc" -eq 0
expect "prints the tunnel command" "ssh -J me@login.example.org me@node001" "$out"
expect "prints the localhost URL" "http://localhost:8888/lab?token=0123abcd" "$out"
expect "prints when the session ends" "Session ends at 2026-11-18 23:15 (time limit)" "$out"
expect "suggests --stop to finish" "launch_jupyter --stop 12345" "$out"
args=$(cat "${FAKE_STATE}/sbatch_args")
expect "passes --cpus-per-task" "--cpus-per-task=2" "$args"
expect "passes --mem" "--mem=4G" "$args"
expect "passes --time" "--time=1:00:00" "$args"
expect "passes --partition" "--partition=testpart" "$args"
expect "job name is jupyter" "--job-name=jupyter" "$args"

echo "== launcher: bold only on a terminal"
ESC=$'\033'
if [[ "$out" != *"${ESC}"* ]]; then pass "piped output has no escape codes"
else fail "piped output has escape codes" "$out"; fi
if command -v script >/dev/null 2>&1; then
    # script(1) runs the launcher on a pseudo-terminal.
    out=$(script -qec "${SCRIPT}" /dev/null 2>&1)
    expect "tunnel command is bold on a terminal" "${ESC}[1m   ssh -J me@login.example.org" "$out"
    expect "URL is bold on a terminal" "${ESC}[1m   http://localhost:8888/lab?token=0123abcd${ESC}[0m" "$out"
    out=$(NO_COLOR=1 script -qec "${SCRIPT}" /dev/null 2>&1)
    if [[ "$out" == *"ssh -J"* && "$out" != *"${ESC}[1m"* ]]; then pass "NO_COLOR turns bold off"
    else fail "NO_COLOR did not turn bold off" "$out"; fi
else
    echo "SKIP: script(1) not found; terminal bold not tested"
fi

echo "== launcher: extra sbatch options after --"
out=$("${SCRIPT}" -- --account=proj 2>&1)
expect "passes options after --" "--account=proj" "$(cat "${FAKE_STATE}/sbatch_args")"

echo "== launcher: placeholder text is not mistaken for the URL"
export FAKE_LOG_CONTENT="2. Open the URL with the token that Jupyter prints below, using localhost\n"
export FAKE_SQUEUE="RUNNING|None"
out=$(LJ_WAIT=1 timeout 20 "${SCRIPT}" 2>&1)
if [[ "$out" != *"Then open in your browser"* ]]; then pass "no URL reported before Jupyter prints one"
else fail "reported a URL from header text" "$out"; fi

echo "== launcher: job fails before Jupyter starts"
export FAKE_LOG_CONTENT="Traceback (most recent call last):\nKeyError: 'so_root'\n"
export FAKE_SQUEUE=""
out=$("${SCRIPT}" 2>&1); rc=$?
check "launcher exits non-zero when the job dies" "$rc" -ne 0
expect "explains the job ended" "ended before it was ready" "$out"
expect "shows the end of the log" "KeyError: 'so_root'" "$out"

echo "== launcher: sbatch rejects the job"
out=$(FAKE_SBATCH_FAIL=1 "${SCRIPT}" 2>&1); rc=$?
check "sbatch failure exits non-zero" "$rc" -ne 0
expect "sbatch failure is reported" "sbatch failed" "$out"

echo "== launcher: no jupyter-lab and no module"
out=$(PATH="${FAKE}:/usr/bin:/bin" bash -c "mv '${FAKE}/jupyter-lab' '${FAKE}/jl.off'; '${SCRIPT}' 2>&1; echo rc=\$?; mv '${FAKE}/jl.off' '${FAKE}/jupyter-lab'")
expect "refuses without jupyter-lab or a module" "jupyter-lab is not on PATH and no module is configured" "$out"

echo "== launcher: VS Code"
export FAKE_LOG_CONTENT="VS Code session ready on node007\n"
export FAKE_SQUEUE="RUNNING|None"
out=$(LJ_SSH_HOST_PATTERN='node*' LJ_LOGIN_HOST=login.example.org "${SCRIPT}" --vscode 2>&1); rc=$?
check "--vscode exits 0 when ready" "$rc" -eq 0
expect "prints ssh config host pattern" "Host node*" "$out"
expect "prints ProxyJump" "ProxyJump" "$out"
expect "names the node to connect to" "enter node007" "$out"
expect "job name is vscode" "--job-name=vscode" "$(cat "${FAKE_STATE}/sbatch_args")"

echo "== --list"
printf '  ssh -J me@login me@node001 -L 9000:127.0.0.1:9000 -N\n[I ServerApp] http://127.0.0.1:9000/lab?token=feed\n' >"${LOG}"
out=$(FAKE_SQUEUE="12345|jupyter|RUNNING|node001|1:00:00|2026-11-18T23:15:00\n99|other|RUNNING|node002|2:00|2026-11-19T01:00:00" \
    FAKE_STDOUT="${LOG}" "${SCRIPT}" --list 2>&1)
expect "--list shows the session" "Job 12345 (jupyter) running on node001" "$out"
expect "--list shows the URL" "http://localhost:9000/lab?token=feed" "$out"
expect "--list shows the end time" "ends:    2026-11-18 23:15 (time limit)" "$out"
if [[ "$out" != *"Job 99"* ]]; then pass "--list ignores other jobs"; else fail "--list showed an unrelated job" "$out"; fi
out=$(FAKE_SQUEUE="" "${SCRIPT}" --list 2>&1)
expect "--list with nothing running" "No running jupyter or vscode sessions" "$out"

echo "== --stop"
rm -f "${scancel_log}"
out=$(FAKE_SQUEUE="12345|jupyter|RUNNING|node001|1:00:00|N/A\n99|other|RUNNING|node002|2:00|N/A" \
    "${SCRIPT}" --stop 2>&1); rc=$?
check "--stop with one session exits 0" "$rc" -eq 0
expect "--stop cancels the only session" "Stopped job 12345 (jupyter)" "$out"
check "--stop called scancel on that job only" "$(cat "${scancel_log}" 2>/dev/null)" = 12345

rm -f "${scancel_log}"
two="12345|jupyter|RUNNING|node001|1:00:00|N/A\n12346|vscode|PENDING||2:00|N/A"
out=$(FAKE_SQUEUE="${two}" "${SCRIPT}" --stop 2>&1); rc=$?
check "--stop with two sessions exits non-zero" "$rc" -ne 0
expect "--stop lists the choices" "launch_jupyter --stop 12346" "$out"
check "--stop with two sessions cancels nothing" ! -e "${scancel_log}"

out=$(FAKE_SQUEUE="${two}" "${SCRIPT}" --stop 12346 2>&1)
expect "--stop JOBID cancels that session" "Stopped job 12346 (vscode)" "$out"

rm -f "${scancel_log}"
out=$(FAKE_SQUEUE="${two}\n99|other|RUNNING|node002|2:00|N/A" "${SCRIPT}" --stop 99 2>&1); rc=$?
check "--stop refuses a job that is not a session" "$rc" -ne 0
expect "--stop explains the refusal" "job 99 is not one of your jupyter or vscode sessions" "$out"
check "--stop did not cancel job 99" ! -e "${scancel_log}"

out=$("${SCRIPT}" --stop abc 2>&1)
expect "--stop rejects a non-numeric ID" "--stop takes a job ID (a number), not 'abc'" "$out"

rm -f "${scancel_log}"
out=$(FAKE_SQUEUE="${two}" "${SCRIPT}" --stop-all 2>&1)
expect "--stop-all stops the first" "Stopped job 12345 (jupyter)" "$out"
expect "--stop-all stops the second" "Stopped job 12346 (vscode)" "$out"
check "--stop-all called scancel twice" "$(wc -l <"${scancel_log}")" -eq 2

out=$(FAKE_SQUEUE="" "${SCRIPT}" --stop 2>&1); rc=$?
check "--stop with nothing running exits 0" "$rc" -eq 0
expect "--stop with nothing running says so" "No running jupyter or vscode sessions" "$out"

echo "== job mode: Jupyter"
JOBLOG="${WORK}/job.log"
: >"${JOBLOG}"; chmod 644 "${JOBLOG}"
out=$(SLURM_JOB_ID=12345 LJ_FROM_LAUNCHER=1 LJ_MODULE='' LJ_MODULEPATH='' \
    LJ_LOGIN_HOST=login.example.org LJ_IDLE_TIMEOUT=0 FAKE_STDOUT="${JOBLOG}" \
    FAKE_END=2026-11-18T23:15:00 "${SCRIPT}" --job 2>&1); rc=$?
check "job mode runs jupyter-lab" "$rc" -eq 0
expect "job header has the ssh tunnel" "ssh -J ${USER:-$(id -un)}@login.example.org" "$out"
expect "job header has the end time" "Session ends at 2026-11-18 23:15" "$out"
jargs=$(cat "${FAKE_STATE}/jupyter_args")
expect "jupyter binds to 127.0.0.1 only" "--ip=127.0.0.1" "$jargs"
expect "jupyter does not open a browser" "--no-browser" "$jargs"
if [[ "$jargs" != *"shutdown_no_activity_timeout"* ]]; then pass "idle shutdown off by default"
else fail "idle shutdown enabled by default" "$jargs"; fi
perm=$(stat -c %a "${JOBLOG}")
check "job log made private (600, got $perm)" "$perm" = 600

echo "== job mode: idle timeout"
SLURM_JOB_ID=12345 LJ_FROM_LAUNCHER=1 LJ_MODULE='' LJ_MODULEPATH='' LJ_LOGIN_HOST=x \
    LJ_IDLE_TIMEOUT=30 FAKE_STDOUT="${JOBLOG}" "${SCRIPT}" --job >/dev/null 2>&1
jargs=$(cat "${FAKE_STATE}/jupyter_args")
expect "idle timeout sets server shutdown (1800 s)" "--ServerApp.shutdown_no_activity_timeout=1800" "$jargs"
expect "idle timeout culls kernels" "--MappingKernelManager.cull_idle_timeout=1800" "$jargs"

echo "== job mode: VS Code cleanup stops only VS Code server processes"
fakeserver_dir="${WORK}/home/.vscode-server/cli/servers/Stable-x/server"
mkdir -p "${fakeserver_dir}"
# A stand-in VS Code server: a copy of bash whose executable lives under
# .vscode-server/, blocking on a FIFO with the read builtin (no child
# process). Not a copy of sleep: multi-call coreutils builds (e.g. uutils
# on newer Ubuntu) pick the tool from the file name and refuse "node".
fifo="${WORK}/fake-server.fifo"
mkfifo "${fifo}"
cp "$(readlink -f "$(command -v bash)")" "${fakeserver_dir}/node"
# shellcheck disable=SC2016  # $1 is expanded by the stand-in bash, not here
"${fakeserver_dir}/node" -c 'read -r -t 300 _ <>"$1"' fake-server "${fifo}" &
vs_pid=$!
sleep 300 &
other_pid=$!
sleep 0.5
if kill -0 "${vs_pid}" 2>/dev/null && [[ "$(readlink "/proc/${vs_pid}/exe")" == */.vscode-server/* ]]; then
    pass "stand-in VS Code server is running"
else
    fail "stand-in VS Code server did not start, so the cleanup test would be meaningless" \
        "exe: $(readlink "/proc/${vs_pid}/exe" 2>&1)"
fi
SLURM_JOB_ID=12345 LJ_FROM_LAUNCHER=1 LJ_MODE=vscode LJ_LOGIN_HOST=x FAKE_STDOUT="${JOBLOG}" \
    "${SCRIPT}" --job >"${WORK}/vscode_job.out" 2>&1 &
job_pid=$!
for _ in $(seq 1 50); do grep -q "session ready" "${WORK}/vscode_job.out" && break; sleep 0.1; done
kill -TERM "${job_pid}"
wait "${job_pid}" 2>/dev/null
sleep 0.5
if kill -0 "${vs_pid}" 2>/dev/null; then fail "VS Code server still running after job ended" "$(cat "${WORK}/vscode_job.out")"
else pass "VS Code server stopped when the job ended"; fi
if kill -0 "${other_pid}" 2>/dev/null; then pass "unrelated process left running"; kill "${other_pid}"
else fail "an unrelated process was killed" ""; fi
expect "cleanup is logged" "stopped 1 VS Code server process(es)" "$(cat "${WORK}/vscode_job.out")"

echo
echo "${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]]
