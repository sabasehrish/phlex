#!/bin/bash
#
# This script prepares a minimal, clean development environment snapshot.
# It is intended to be run once by an administrator with root privileges
# to create a "golden image" or container base.
#
# The script will:
#   1. Install all necessary system and Spack dependencies.
#   2. Perform an aggressive cleanup of all caches and temporary files.
#
# WARNING: This script is destructive and will remove cache files.
# It should only be run in a dedicated environment for snapshot creation.
#
# Usage: sudo ./scripts/prepare-snapshot.sh

set -euo pipefail

echo "Starting environment snapshot preparation..."

# Fail fast if not run as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo." >&2
    exit 1
fi

# --- Environment Setup Phase ---

echo "--- 1. Installing System Dependencies ---"
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gnupg \
    locales-all

echo "--- 2. Setting up Spack ---"
# This script assumes it's being run from the root of the phlex repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the setup script to get environment variables and functions
# We need to unset the error trap temporarily because the setup script sets its own
trap - ERR
# shellcheck source=/dev/null
. "${PROJECT_ROOT}/scripts/setup-env.sh"
trap 'echo "An error occurred. Exiting." >&2; exit 1' ERR

# Now, install all the dependencies defined in the environment
echo "--- 3. Installing Spack Packages ---"
echo "This will take a while..."
spack -e "${SPACK_ENV}" install --fail-fast

echo "--- 4. Installing Ancillary Python Tools ---"
# The Dockerfile installs ruff via pip. We'll do the same.
# We need to find the python from the spack environment to install ruff into it.
spack_python=$(spack -e "${SPACK_ENV}" find --path python | grep -o '/.*' | head -n 1)
if [[ -z "${spack_python}" ]]; then
    echo "Could not find Python in the Spack environment. Skipping ruff installation." >&2
else
    pip_executable="${spack_python}/bin/pip"
    echo "Installing ruff using pip from ${pip_executable}"
    PYTHONDONTWRITEBYTECODE=1 "${pip_executable}" --isolated --no-input --disable-pip-version-check --no-cache-dir install ruff
fi


# --- Environment Cleanup Phase ---
echo "--- 5. Cleaning Caches to Minimize Snapshot Size ---"

# Clean all spack caches (downloads, staged files, etc.)
echo "Cleaning Spack caches..."
spack clean --all

# Clean apt caches
echo "Cleaning apt caches..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Snapshot preparation complete."
