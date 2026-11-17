# launch_jupyter

Start JupyterLab on a Slurm compute node and get the SSH tunnel command and
URL to open it from your laptop, all in one step.

```console
$ launch_jupyter
Submitted job 12345: 8 CPUs, 64G, 12:00:00 on jupyter,main
Log: /home/me/.local/state/launch_jupyter/jupyter-12345.log
Waiting in queue (reason: Resources)...

1. On your local machine, open the tunnel (leave it running):
   ssh -J me@login.example.org me@node042 -L 8731:127.0.0.1:8731 -N
2. Then open in your browser:
   http://localhost:8731/lab?token=3f9c...

Stop the job when finished: scancel 12345
```

## Usage

```
launch_jupyter [options] [-- extra sbatch options]

  -c, --cpus N          CPUs for the job              (default 8)
  -m, --mem SIZE        Memory, e.g. 32G              (default 64G)
  -t, --time TIME       Time limit, e.g. 4:00:00      (default 12:00:00)
  -p, --partition LIST  Slurm partition(s)            (default jupyter,main)
  -M, --module NAME     Module to load if jupyter-lab is not on PATH
  -w, --wait SECONDS    How long to wait for Jupyter to start (default 600)
  -i, --idle-timeout MIN
                        End the session after MIN idle minutes (default 0 = off)
  -l, --list            Show your running sessions and how to connect to them
      --vscode          Hold a node for VS Code Remote-SSH (see below)
  -h, --help            Show help
```

Examples:

```bash
launch_jupyter -c 16 -m 128G -t 1-00:00:00     # bigger and longer
launch_jupyter -p main -- --account=myproject  # extra sbatch options after --
```

**Which Python environment?** If `jupyter-lab` is on your `PATH` when you run
the script (for example, you activated a conda env or loaded a module), the
job uses that environment. Otherwise it loads the module set by the site
(`LJ_MODULE`) or by `-M`.

**Submitting it directly.** The script is also a normal batch script:

```bash
sbatch launch_jupyter                       # uses the #SBATCH defaults in the file
sbatch -c 16 --mem=128G launch_jupyter      # override them as usual
```

The tunnel command and URL are then written to `jupyter-<jobid>.log` in the
directory you submitted from.

## VS Code

`launch_jupyter --vscode` holds a compute node for a VS Code
[Remote-SSH](https://code.visualstudio.com/docs/remote/ssh) session instead of
starting Jupyter. The resource options work the same way.

```console
$ launch_jupyter --vscode -c 4 -t 4:00:00
Submitted job 12346: 4 CPUs, 64G, 4:00:00 on jupyter,main

One-time setup: add this to ~/.ssh/config on your local machine:
  Host node*
      User me
      ProxyJump me@login.example.org

Then in VS Code: Remote-SSH: Connect to Host... and enter node042
```

After the one-time ssh setup, each session is just: run
`launch_jupyter --vscode`, then connect VS Code to the node it prints.

When the job ends (`scancel` or the time limit), the VS Code server on that
node is stopped, so save your work first. This also closes any other VS Code
window you have connected to the same node.

**Note for admins:** without
[`pam_slurm_adopt`](https://slurm.schedmd.com/pam_slurm_adopt.html), the SSH
session is not part of the job, so the VS Code server is not limited to the
job's CPUs and memory. Stopping it when the job ends is the script's best
effort. With `pam_slurm_adopt` the session is adopted into the job and
everything is enforced by Slurm; the script works the same either way.

**Stopping.** Run `scancel <jobid>` when you are done. Pressing Ctrl-C while
the launcher is still waiting asks whether to cancel the job.

**Lost the URL?** `launch_jupyter --list` shows your running sessions with
their tunnel command and URL (or node, for VS Code).

**Idle shutdown (off by default).** With `-i 60`, Jupyter culls idle kernels
and terminals and then shuts down after 60 minutes with no activity, which
ends the job and frees the node. Sites can set a default with
`LJ_IDLE_TIMEOUT`; `-i 0` turns it off.

## Installation

The script is a single file. Put it somewhere on `PATH`:

```bash
git clone https://github.com/josephwkania/launch_jupyter.git /opt/launch_jupyter
ln -s /opt/launch_jupyter/launch_jupyter /usr/local/bin/launch_jupyter
```

To set site defaults, copy `config.example.sh` to `config.sh` **next to the
real script** (the symlink is followed) and edit it. Users can add their own
`~/.config/launch_jupyter/config.sh`; command-line options override both.

Requirements: bash 4+, Slurm (`sbatch`, `squeue`, `scontrol`), JupyterLab
in the user's environment or in a module, and `shuf` and `ss` on compute
nodes (`ss` is optional).

## Configuration

See [`config.example.sh`](config.example.sh). The most useful settings:

| Variable | Purpose | Default |
|---|---|---|
| `LJ_LOGIN_HOST` | Jump host in the printed `ssh -J` command | submit host |
| `LJ_PARTITION` | Partition(s) | `jupyter,main` |
| `LJ_CPUS`, `LJ_MEM`, `LJ_TIME` | Default resources | `8`, `64G`, `12:00:00` |
| `LJ_SSH_HOST_PATTERN` | Host pattern in the printed `~/.ssh/config` (VS Code mode) | the node name |
| `LJ_MODULEPATH`, `LJ_MODULE` | Module to load when `jupyter-lab` is not on `PATH` | none |
| `LJ_IDLE_TIMEOUT` | Minutes of inactivity before Jupyter shuts down (0 = off) | `0` |
| `LJ_LOG_DIR` | Where job logs go | `~/.local/state/launch_jupyter` |

## Troubleshooting

- **"jupyter-lab is not on PATH and no module is configured"**: activate an
  environment that has JupyterLab, or pass `-M <module>`.
- **The job ends straight away**: the launcher prints the end of the log.
  Common causes are an invalid partition or memory request, or the module
  failing to load.
- **Stuck in the queue**: the launcher shows the Slurm reason. Try
  `-p` with another partition or ask for fewer resources.
- **The browser can't connect**: the `ssh` tunnel must keep running while you
  use Jupyter, and the port in the URL must match the one in the ssh command.

## Security

Jupyter listens only on `127.0.0.1` on the compute node and keeps its default
token authentication, so it is reachable only through your SSH tunnel with
the token in the URL. Other users on the same node can reach `127.0.0.1`, so
the token matters: do not turn it off. The job makes its log file, which
contains the token, readable only by you, even when it is written to a
shared directory.

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE). Originally based on
[devanshkv/bowser_slurm_tutorial](https://github.com/devanshkv/bowser_slurm_tutorial)
(GPL-3.0).
