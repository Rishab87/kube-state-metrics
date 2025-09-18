#!/bin/bash
set -exuo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )
CHANGELOG_FILE="${REPO_ROOT}/CHANGELOG.md"

# Check if a version argument was provided
if [ -z "$1" ]; then
    echo "Error: A version argument is required (e.g., v2.10.0)." >&2
    exit 1
fi
new_version=$1

# Determine the OS to use the correct version of sed.
# shellcheck disable=SC2209
SED=sed
if [[ $(uname) == "Darwin" ]]; then
  # Check if gnu-sed is installed.
  if ! command -v gsed &> /dev/null; then
      echo "gnu-sed is not installed. Please install it using 'brew install gnu-sed'." >&2
      exit 1
  fi
  SED=gsed
fi

# Insert the new version after the "Unreleased" section
$SED -i "/## Unreleased/a\\
\\
## $new_version / $(date +'%Y-%m-%d')" "${CHANGELOG_FILE}"

echo "CHANGELOG.md updated successfully."
