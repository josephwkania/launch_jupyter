# launch_jupyter

[![CI](https://github.com/josephwkania/launch_jupyter/actions/workflows/ci.yml/badge.svg)](https://github.com/josephwkania/launch_jupyter/actions/workflows/ci.yml)

Start JupyterLab (or a VS Code Remote-SSH session) on a Slurm compute node
with one command, and get the SSH tunnel and URL to reach it.

```console
$ launch_jupyter
Submitted job 12345: 8 CPUs, 64G, 12:00:00 on jupyter,main
Waiting in queue (reason: Resources)...

1. On your local machine, open the tunnel (leave it running):
   ssh -J me@login.example.org me@node042 -L 8731:127.0.0.1:8731 -N
2. Then open in your browser:
   http://localhost:8731/lab?token=3f9c...

Session ends at 2026-11-18 23:15 (time limit); save your work before then.
Stop the job when finished: launch_jupyter --stop 12345
```

## Usage

```
launch_jupyter [options] [-- extra sbatch options]

  -c, --cpus N          CPUs                       (default 8)
  -m, --mem SIZE        Memory, e.g. 32G           (default 64G)
  -t, --time TIME       Time limit, e.g. 4:00:00   (default 12:00:00)
  -p, --partition LIST  Partition(s)               (default jupyter,main)
  -M, --module NAME     Module to load if jupyter-lab is not on PATH
  -i, --idle-timeout M  Stop after M idle minutes  (default 0 = off)
  -l, --list            Show running sessions and how to connect
  -s, --stop [JOBID]    Stop a session (the only one, if no JOBID)
      --stop-all        Stop all your sessions
      --vscode          Hold a node for VS Code Remote-SSH instead
  -w, --wait SECONDS    How long to wait for startup (default 600)
```

- **Environment:** if `jupyter-lab` is on your `PATH` (e.g. an activated conda
  env), the job uses it; otherwise it loads the configured or `-M` module.
- **As a batch script:** `sbatch launch_jupyter` also works; the connection
  details go to `jupyter-<jobid>.log` in the submit directory.
- **Stopping:** `launch_jupyter --stop` (or `scancel <jobid>`). Ctrl-C while
  waiting offers to cancel. The session's end time (its time limit) is printed
  when it starts and by `--list`.
- **Lost the URL?** `launch_jupyter --list`.

## Using your own environment

**Run Jupyter from your env:** activate it first. If it has `jupyter-lab`, the
job uses it:

```bash
conda activate myenv          # needs jupyterlab installed in it
launch_jupyter
```

**Or add your env as a kernel**, to keep the site's Jupyter and pick your env
from the kernel list (once per env):

```bash
conda activate myenv
conda install ipykernel       # or: pip install ipykernel
python -m ipykernel install --user --name myenv --display-name "Python (myenv)"
```

It appears in the Launcher and under *Kernel → Change Kernel* the next time
you start Jupyter. `jupyter kernelspec list` shows your kernels and
`jupyter kernelspec uninstall myenv` removes one. Kernels live in
`~/.local/share/jupyter/kernels/`, so they are available on every node.

## VS Code

`launch_jupyter --vscode` holds a node and prints a one-time
`~/.ssh/config` entry, two VS Code settings and the node to connect to with
[Remote-SSH](https://code.visualstudio.com/docs/remote/ssh):

```console
$ launch_jupyter --vscode -t 4:00:00
One-time setup on your local machine. Add this to ~/.ssh/config:
  Host node*
      User me
      ProxyJump me@login.example.org
      StrictHostKeyChecking accept-new
and these to your VS Code settings.json:
  "remote.SSH.maxReconnectionAttempts": 2,
  "remote.SSH.useFlock": false

Then in VS Code: Remote-SSH: Connect to Host... and enter node042
```

- `StrictHostKeyChecking accept-new` skips the host-key prompt the first time
  you reach each node, but still refuses a node whose key has changed.
- `maxReconnectionAttempts` makes VS Code give up soon after the job ends,
  instead of retrying.
- `useFlock: false`: VS Code locks files in its server directory, which can
  fail when home is on a network filesystem (NFS) as compute nodes see it.

The VS Code server installs into `~/.vscode-server` (a few hundred MB per VS
Code version); if your home directory is over quota, connecting fails.
Delete old versions under `~/.vscode-server/cli/servers/` to free space.

When the job ends, your VS Code server on that node is stopped, so save
first. Without
[`pam_slurm_adopt`](https://slurm.schedmd.com/pam_slurm_adopt.html) the SSH
session is outside the job's resource limits; with it, Slurm enforces them.

## Installation and configuration

```bash
git clone https://github.com/josephwkania/launch_jupyter.git /opt/launch_jupyter
ln -s /opt/launch_jupyter/launch_jupyter /usr/local/bin/launch_jupyter
```

Site defaults go in `config.sh` next to the real script (copy
[`config.example.sh`](config.example.sh)); users can override them in
`~/.config/launch_jupyter/config.sh`, and options override both. Key settings:
`LJ_LOGIN_HOST` (jump host), `LJ_PARTITION`, `LJ_CPUS`/`LJ_MEM`/`LJ_TIME`,
`LJ_MODULEPATH`/`LJ_MODULE`, `LJ_SSH_HOST_PATTERN` (VS Code) and
`LJ_IDLE_TIMEOUT`.

Requires bash 4+, Slurm (`sbatch`, `squeue`, `scontrol`), JupyterLab in the
user's environment or a module, and `shuf` (and optionally `ss`) on nodes.

## Troubleshooting

- **Job ends straight away:** the launcher prints the end of the log. Usually
  a bad partition or memory request, or the module failing to load.
- **Stuck in the queue:** the Slurm reason is shown; try another `-p` or fewer
  resources.
- **Browser can't connect:** keep the `ssh` tunnel running, and check the
  port matches the URL.
- **ssh refuses a node ("REMOTE HOST IDENTIFICATION HAS CHANGED"):** the
  node was probably reinstalled. Run `ssh-keygen -R <node>` and reconnect.

## Security

Jupyter listens only on `127.0.0.1` with token authentication, so it is
reachable only through your tunnel. Other users on the node can reach
`127.0.0.1`, so keep the token on. The log holding the token is made
readable only by you.

## Development

```bash
bash tests/run_tests.sh    # no cluster needed: Slurm and Jupyter are faked
shellcheck launch_jupyter config.example.sh tests/run_tests.sh
```

CI runs both on Ubuntu and Rocky Linux 9.

## Licence

GPL-3.0-or-later ([LICENSE](LICENSE)). Originally based on
[devanshkv/bowser_slurm_tutorial](https://github.com/devanshkv/bowser_slurm_tutorial).
