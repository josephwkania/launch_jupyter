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
      --vscode          Hold a node for VS Code Remote-SSH instead
  -w, --wait SECONDS    How long to wait for startup (default 600)
```

- **Environment:** if `jupyter-lab` is on your `PATH` (e.g. an activated conda
  env), the job uses it; otherwise it loads the configured or `-M` module.
- **As a batch script:** `sbatch launch_jupyter` also works; the connection
  details go to `jupyter-<jobid>.log` in the submit directory.
- **Stopping:** `scancel <jobid>`. Ctrl-C while waiting offers to cancel.
- **Lost the URL?** `launch_jupyter --list`.

## VS Code

`launch_jupyter --vscode` holds a node and prints a one-time
`~/.ssh/config` entry and the node to connect to with
[Remote-SSH](https://code.visualstudio.com/docs/remote/ssh):

```console
$ launch_jupyter --vscode -t 4:00:00
One-time setup: add this to ~/.ssh/config on your local machine:
  Host node*
      User me
      ProxyJump me@login.example.org

Then in VS Code: Remote-SSH: Connect to Host... and enter node042
```

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
