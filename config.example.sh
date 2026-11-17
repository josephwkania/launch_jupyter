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

# Seconds to wait for Jupyter to start before giving up waiting (the job is
# left running). Default: 600
# LJ_WAIT=600
