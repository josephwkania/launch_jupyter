# shellcheck shell=bash
# launch_jupyter configuration
#
# Copy this file to one of:
#   <directory of the launch_jupyter script>/config.sh   site-wide defaults (admins)
#   ~/.config/launch_jupyter/config.sh                   your own defaults
# or point LAUNCH_JUPYTER_CONFIG at any file. The user file is read after the
# site file, and command-line options override both. Every setting is
# optional; anything left unset uses the default shown.

# Host users SSH to from outside the cluster; used as the jump host in the
# printed tunnel command. Default: the host the job was submitted from.
# LJ_LOGIN_HOST=login.example.org

# --vscode mode: the Host pattern printed in the suggested ~/.ssh/config entry.
# A pattern that matches all compute nodes (e.g. 'node*') means users only
# set up ssh once. Default: the name of the node the job landed on.
# LJ_SSH_HOST_PATTERN='node*'

# Slurm partition(s), comma separated. Default: jupyter,main
# LJ_PARTITION=jupyter,main

# Default resources. Defaults: 8 CPUs, 64G, 12 hours
# LJ_CPUS=8
# LJ_MEM=64G
# LJ_TIME=12:00:00

# Environment module to load when jupyter-lab is not already on the user's
# PATH, plus an optional extra module path. Default: none (the user must
# activate an environment with JupyterLab first).
# LJ_MODULEPATH=/opt/modulefiles
# LJ_MODULE=python/jupyter

# Where launcher-mode job logs go. Default: ~/.local/state/launch_jupyter
# LJ_LOG_DIR="$HOME/.local/state/launch_jupyter"

# Stop Jupyter, which ends the job, after this many minutes with no activity
# (idle kernels and terminals are culled first). 0 turns it off. Users can
# override with -i/--idle-timeout. Not used in --vscode mode. Default: 0 (off)
# LJ_IDLE_TIMEOUT=0

# Seconds to wait for Jupyter to start before giving up waiting (the job is
# left running). Default: 600
# LJ_WAIT=600
