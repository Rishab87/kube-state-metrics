#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )
DATA_FILE="${REPO_ROOT}/data.yaml"
NUM_RELEASES_TO_KEEP=5

check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: Required command '$1' not found. Please install it to continue." >&2
        exit 1
    fi
}

check_command "yq"
check_command "jq"
check_command "curl"
check_command "sort"

if [ -z "$1" ]; then
    echo "Usage: $0 <new_version>"
    echo "Example: $0 v2.17.0"
    exit 1
fi

if [ ! -f "${DATA_FILE}" ]; then
    echo "Error: Data file not found at ${DATA_FILE}" >&2
    exit 1
fi

NEW_VERSION_WITH_V=$1
CLEAN_NEW_VERSION=${NEW_VERSION_WITH_V#v}

echo "Starting update process for version ${NEW_VERSION_WITH_V}..."

echo "Fetching latest Kubernetes version..."
LATEST_K8S_FULL_VERSION=$(curl --silent --fail "https://api.github.com/repos/kubernetes/kubernetes/releases/latest" | jq -r '.tag_name')

if [ -z "$LATEST_K8S_FULL_VERSION" ] || [ "$LATEST_K8S_FULL_VERSION" == "null" ]; then
    echo "Error: Failed to fetch the latest Kubernetes version from GitHub." >&2
    exit 1
fi

LATEST_K8S_VERSION=$(echo "${LATEST_K8S_FULL_VERSION}" | sed 's/^v//' | cut -d. -f1,2)
echo "Latest stable Kubernetes version (N): ${LATEST_K8S_VERSION}"

K8S_MAJOR=$(echo "${LATEST_K8S_VERSION}" | cut -d. -f1)
K8S_MINOR=$(echo "${LATEST_K8S_VERSION}" | cut -d. -f2)
PREV_K8S_MINOR=$((K8S_MINOR - 1))
K8S_VERSION_FOR_NEW_RELEASE="${K8S_MAJOR}.${PREV_K8S_MINOR}"
echo "New release ${NEW_VERSION_WITH_V} will be mapped to Kubernetes (N-1): ${K8S_VERSION_FOR_NEW_RELEASE}"


EXISTING_EXACT_MATCH=$(yq eval ".compat[] | select(.version == \"${NEW_VERSION_WITH_V}\" and .kubernetes == \"${K8S_VERSION_FOR_NEW_RELEASE}\")" "${DATA_FILE}")

if [ -n "${EXISTING_EXACT_MATCH}" ]; then
    echo "Entry for ${NEW_VERSION_WITH_V} with Kubernetes ${K8S_VERSION_FOR_NEW_RELEASE} already exists. No changes needed."
    exit 0
fi

EXISTING_KSM_VERSION_ENTRY=$(yq eval ".compat[] | select(.version == \"${NEW_VERSION_WITH_V}\")" "${DATA_FILE}")

if [ -n "${EXISTING_KSM_VERSION_ENTRY}" ]; then
    echo "Version ${NEW_VERSION_WITH_V} found with a different K8s mapping. Updating..."
    # Update the kubernetes version for the existing entry
    yq eval "(.compat[] | select(.version == \"${NEW_VERSION_WITH_V}\")).kubernetes = \"${K8S_VERSION_FOR_NEW_RELEASE}\"" -i "${DATA_FILE}"
    # Also update the top-level version key and the main branch k8s version to keep everything current
    yq eval ".version = \"${CLEAN_NEW_VERSION}\"" -i "${DATA_FILE}"
    yq eval "(.compat[] | select(.version == \"main\")).kubernetes = \"${LATEST_K8S_VERSION}\"" -i "${DATA_FILE}"
    echo "Successfully updated existing entry for ${NEW_VERSION_WITH_V}."
    echo "--- Final ${DATA_FILE} content ---"
    cat "${DATA_FILE}"
    exit 0
fi

echo "Adding new version ${NEW_VERSION_WITH_V} and pruning old releases..."

TEMP_FILE=$(mktemp)
trap 'rm -f ${TEMP_FILE}' EXIT

cat > "${TEMP_FILE}" << EOF
# The purpose of this config is to keep all versions in a single file and make them machine accessible

# Marks the latest release
version: "${CLEAN_NEW_VERSION}"

# List at max ${NUM_RELEASES_TO_KEEP} releases here + the main branch
compat:
EOF

{
    yq eval '.compat[] | select(.version != "main") | [.version, .kubernetes] | join("|")' "${DATA_FILE}" 2>/dev/null || true
    echo "${NEW_VERSION_WITH_V}|${K8S_VERSION_FOR_NEW_RELEASE}"
} | sort -t'|' -k1,1 -Vr | head -n "${NUM_RELEASES_TO_KEEP}" | sort -t'|' -k1,1 -V | while IFS='|' read -r version k8s_ver; do
    echo "  - version: \"${version}\"" >> "${TEMP_FILE}"
    echo "    kubernetes: \"${k8s_ver}\"" >> "${TEMP_FILE}"
done

cat >> "${TEMP_FILE}" << EOF
  - version: "main"
    kubernetes: "${K8S_VERSION_FOR_NEW_RELEASE}"
EOF

mv "${TEMP_FILE}" "${DATA_FILE}"

echo "Successfully updated and pruned ${DATA_FILE}."
echo "New release (${NEW_VERSION_WITH_V}) is mapped to Kubernetes: ${K8S_VERSION_FOR_NEW_RELEASE}"
echo "Main branch is mapped to Kubernetes: ${K8S_VERSION_FOR_NEW_RELEASE}"
echo "--- Final ${DATA_FILE} content ---"
cat "${DATA_FILE}"