#!/bin/bash
#
# Test script for entrypoint.sh
# Simulates the GitHub Actions environment locally
#
# Usage:
#   ./test-entrypoint.sh <repo_name> <source_branch> [target_branch=testing]
#
# Examples:
#   ./test-entrypoint.sh aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver
#   ./test-entrypoint.sh aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver testing
#   ./test-entrypoint.sh aws.appsync.compass-select hotfix/eng-1158-inconsistent-response production
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
REPO_NAME="${1}"
SOURCE_BRANCH="${2}"
TARGET_BRANCH="${3:-testing}"

# Validate required arguments
if [ -z "${REPO_NAME}" ] || [ -z "${SOURCE_BRANCH}" ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <repo_name> <source_branch> [target_branch]"
    echo ""
    echo "Arguments:"
    echo "  repo_name       Repository name (without bricklanetech/ prefix)"
    echo "  source_branch   The branch being merged (e.g., feature/my-feature)"
    echo "  target_branch   The branch being merged into (default: testing)"
    echo ""
    echo "Examples:"
    echo "  $0 aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver"
    echo "  $0 aws.appsync.compass-select testing production"
    exit 1
fi

# Configuration
GITHUB_ORG="bricklanetech"
REPO_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"
TEST_DIR="/tmp/control-merge-test-${REPO_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT_SCRIPT="${SCRIPT_DIR}/entrypoint.sh"

echo -e "${YELLOW}=== Control Merge Action Test ===${NC}"
echo ""
echo "Repository:    ${GITHUB_ORG}/${REPO_NAME}"
echo "Source branch: ${SOURCE_BRANCH}"
echo "Target branch: ${TARGET_BRANCH}"
echo "Test dir:      ${TEST_DIR}"
echo ""

# Check entrypoint script exists
if [ ! -f "${ENTRYPOINT_SCRIPT}" ]; then
    echo -e "${RED}Error: entrypoint.sh not found at ${ENTRYPOINT_SCRIPT}${NC}"
    exit 1
fi

# Clean up previous test directory
echo -e "${YELLOW}-> Preparing test environment${NC}"
rm -rf "${TEST_DIR}"

# Clone repository with shallow clone (simulates GitHub Actions checkout)
echo -e "${YELLOW}-> Cloning repository (shallow clone to simulate GitHub Actions)${NC}"
if ! git clone --depth=1 "${REPO_URL}" "${TEST_DIR}" 2>&1; then
    echo -e "${RED}Error: Failed to clone repository${NC}"
    exit 1
fi

# Set up GitHub Actions environment variables
echo -e "${YELLOW}-> Setting up environment variables${NC}"
export GITHUB_HEAD_REF="${SOURCE_BRANCH}"
export GITHUB_BASE_REF="${TARGET_BRANCH}"
export INPUT_WORKFLOW="testing production"
export INPUT_HOTFIX_PATTERN="hotfix/*"
export INPUT_FEATURE_PATTERN="feature/*"
export GITHUB_OUTPUT="/dev/stdout"

echo "  GITHUB_HEAD_REF=${GITHUB_HEAD_REF}"
echo "  GITHUB_BASE_REF=${GITHUB_BASE_REF}"
echo "  INPUT_WORKFLOW=${INPUT_WORKFLOW}"
echo "  INPUT_HOTFIX_PATTERN=${INPUT_HOTFIX_PATTERN}"
echo "  INPUT_FEATURE_PATTERN=${INPUT_FEATURE_PATTERN}"
echo ""

# Change to test directory
cd "${TEST_DIR}"

# Run the entrypoint script (replacing /github/workspace with test directory)
echo -e "${YELLOW}-> Running entrypoint.sh${NC}"
echo "----------------------------------------"

# Create a modified version of the script for local testing
TEMP_SCRIPT=$(mktemp)
sed "s|/github/workspace|${TEST_DIR}|g" "${ENTRYPOINT_SCRIPT}" > "${TEMP_SCRIPT}"
chmod +x "${TEMP_SCRIPT}"

# Run the script and capture exit code
set +e
bash "${TEMP_SCRIPT}"
EXIT_CODE=$?
set -e

echo "----------------------------------------"
echo ""

# Clean up temp script
rm -f "${TEMP_SCRIPT}"

# Report result
if [ ${EXIT_CODE} -eq 0 ]; then
    echo -e "${GREEN}✔ Test PASSED (exit code: ${EXIT_CODE})${NC}"
else
    echo -e "${RED}✘ Test FAILED (exit code: ${EXIT_CODE})${NC}"
fi

# Optional: Clean up test directory
# rm -rf "${TEST_DIR}"

exit ${EXIT_CODE}
