#!/bin/bash
#
# Test script for entrypoint.sh
# Simulates the GitHub Actions environment locally
#
# This script automatically detects the workflow configuration from the repository's
# GitHub Actions workflow files (looks for 'workflow:' in .github/workflows/*.yml)
#
# Usage:
#   ./test-entrypoint.sh <repo_name> <source_branch> [target_branch] [--workflow "branch1 branch2 ..."]
#
# Arguments:
#   repo_name       Repository name (without bricklanetech/ prefix)
#   source_branch   The branch being merged (e.g., feature/my-feature)
#   target_branch   The branch being merged into (default: first branch in detected workflow, or "testing")
#   --workflow      Override: space-separated list of workflow branches (auto-detected from repo if not provided)
#
# Examples:
#   # Auto-detect workflow from repo
#   ./test-entrypoint.sh aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver
#   ./test-entrypoint.sh aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver testing
#
#   # Override with custom workflow
#   ./test-entrypoint.sh aws.appsync.compass-select feature/my-feature develop --workflow "develop staging main"
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fallback workflow if not detected from repo
FALLBACK_WORKFLOW="testing production"

# Parse arguments
REPO_NAME=""
SOURCE_BRANCH=""
TARGET_BRANCH=""
WORKFLOW=""

# Parse positional and flag arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workflow)
            WORKFLOW="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 <repo_name> <source_branch> [target_branch] [--workflow \"branch1 branch2 ...]\]"
            echo ""
            echo "Run '$0' without arguments for detailed help."
            exit 0
            ;;
        *)
            # Positional arguments
            if [ -z "${REPO_NAME}" ]; then
                REPO_NAME="$1"
            elif [ -z "${SOURCE_BRANCH}" ]; then
                SOURCE_BRANCH="$1"
            elif [ -z "${TARGET_BRANCH}" ]; then
                TARGET_BRANCH="$1"
            fi
            shift
            ;;
    esac
done

# Apply defaults (target branch default applied after workflow detection)
WORKFLOW_OVERRIDE="${WORKFLOW}"

# Validate required arguments
if [ -z "${REPO_NAME}" ] || [ -z "${SOURCE_BRANCH}" ]; then
    echo -e "${RED}❌ Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <repo_name> <source_branch> [target_branch] [--workflow \"branch1 branch2 ...\"]"
    echo ""
    echo "Arguments:"
    echo "  repo_name       Repository name (without bricklanetech/ prefix)"
    echo "  source_branch   The branch being merged (e.g., feature/my-feature)"
    echo "  target_branch   The branch being merged into (default: auto-detected from repo)"
    echo "  --workflow      Override workflow (auto-detected from repo's .github/workflows/*.yml)"
    echo ""
    echo "Examples:"
    echo "  # Auto-detect workflow from repo"
    echo "  $0 aws.appsync.compass-select feature/eng-976-create-adjust-js-resolver"
    echo "  $0 aws.appsync.compass-select testing production"
    echo ""
    echo "  # Override workflow"
    echo "  $0 aws.appsync.compass-select feature/my-feature develop --workflow \"develop staging main\""
    exit 1
fi

# Configuration
GITHUB_ORG="bricklanetech"
REPO_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}.git"
TEST_DIR="/tmp/control-merge-test-${REPO_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT_SCRIPT="${SCRIPT_DIR}/entrypoint.sh"

# Check entrypoint script exists
if [ ! -f "${ENTRYPOINT_SCRIPT}" ]; then
    echo -e "${RED}❌ Error: entrypoint.sh not found at ${ENTRYPOINT_SCRIPT}${NC}"
    exit 1
fi

# Clean up previous test directory
echo -e "${YELLOW}🧹 Preparing test environment${NC}"
rm -rf "${TEST_DIR}"

# Clone repository with shallow clone (simulates GitHub Actions checkout)
echo -e "${YELLOW}📥 Cloning repository (shallow clone to simulate GitHub Actions)${NC}"
if ! git clone --depth=1 "${REPO_URL}" "${TEST_DIR}" 2>&1; then
    echo -e "${RED}❌ Error: Failed to clone repository${NC}"
    echo -e "${RED}   Check that '${REPO_NAME}' is correct and you have access to ${REPO_URL}${NC}"
    exit 1
fi

# Change to test directory
cd "${TEST_DIR}"

# Auto-detect workflow from repo's GitHub Actions workflow files
if [ -z "${WORKFLOW_OVERRIDE}" ]; then
    echo -e "${YELLOW}🔎 Auto-detecting workflow from .github/workflows/*.yml${NC}"

    # Look for 'workflow:' in workflow files and extract the value
    # NOTE: This assumes single-line YAML syntax (e.g., "workflow: testing production")
    #       Multiline YAML arrays (workflow:\n  - testing\n  - production) are NOT supported
    #       and will fall back to FALLBACK_WORKFLOW
    DETECTED_WORKFLOW=""
    if [ -d ".github/workflows" ]; then
        # Search for workflow: configuration in yml files
        DETECTED_WORKFLOW=$(grep -rh "workflow:" .github/workflows/*.yml 2>/dev/null | \
            head -1 | \
            sed 's/.*workflow:[[:space:]]*//' | \
            tr -d '\r' | \
            xargs)
    fi

    if [ -n "${DETECTED_WORKFLOW}" ]; then
        WORKFLOW="${DETECTED_WORKFLOW}"
        echo -e "${GREEN}   ✅ Detected workflow: ${WORKFLOW}${NC}"
    else
        WORKFLOW="${FALLBACK_WORKFLOW}"
        echo -e "${YELLOW}   ⚠️  Could not detect workflow, using fallback: ${WORKFLOW}${NC}"
    fi
else
    WORKFLOW="${WORKFLOW_OVERRIDE}"
    echo -e "${BLUE}   ℹ️  Using provided workflow: ${WORKFLOW}${NC}"
fi

# Apply target branch default (first branch in workflow)
# Using read -ra to safely split into array (avoids SC2206 shellcheck warning)
read -ra WORKFLOW_ARRAY <<< "${WORKFLOW}"
if [ -z "${TARGET_BRANCH}" ]; then
    TARGET_BRANCH="${WORKFLOW_ARRAY[0]}"
    echo -e "${BLUE}   ℹ️  Target branch defaulting to first workflow branch: ${TARGET_BRANCH}${NC}"
fi

# Validate workflow has at least 2 branches
if [ ${#WORKFLOW_ARRAY[@]} -lt 2 ]; then
    echo -e "${RED}❌ Error: Workflow must have at least 2 branches${NC}"
    echo -e "${RED}   Got: '${WORKFLOW}'${NC}"
    echo ""
    echo "Example: --workflow \"testing production\" or --workflow \"develop staging main\""
    exit 1
fi

# Validate target branch is in the workflow
TARGET_IN_WORKFLOW=false
for branch in "${WORKFLOW_ARRAY[@]}"; do
    if [ "${branch}" = "${TARGET_BRANCH}" ]; then
        TARGET_IN_WORKFLOW=true
        break
    fi
done

if [ "${TARGET_IN_WORKFLOW}" = false ]; then
    echo -e "${RED}❌ Error: Target branch '${TARGET_BRANCH}' is not in the workflow${NC}"
    echo -e "${RED}   Workflow: ${WORKFLOW}${NC}"
    echo ""
    echo "Either:"
    echo "  1. Change target_branch to one of: ${WORKFLOW}"
    echo "  2. Use --workflow to specify a workflow that includes '${TARGET_BRANCH}'"
    exit 1
fi

echo ""
echo -e "${YELLOW}🧪 === Control Merge Action Test ===${NC}"
echo ""
echo "📦 Repository:    ${GITHUB_ORG}/${REPO_NAME}"
echo "🌿 Source branch: ${SOURCE_BRANCH}"
echo "🎯 Target branch: ${TARGET_BRANCH}"
echo "🔀 Workflow:      ${WORKFLOW}"
echo "📁 Test dir:      ${TEST_DIR}"
echo ""

# Verify SOURCE_BRANCH exists
echo -e "${YELLOW}🔍 Verifying source branch exists: ${SOURCE_BRANCH}${NC}"
if ! git rev-parse --verify "origin/${SOURCE_BRANCH}" >/dev/null 2>&1; then
    echo -e "${YELLOW}   ⏳ Branch not in shallow clone, fetching...${NC}"
    if ! git fetch origin "${SOURCE_BRANCH}:refs/remotes/origin/${SOURCE_BRANCH}" --depth=1 2>&1; then
        echo -e "${RED}❌ Error: Source branch '${SOURCE_BRANCH}' does not exist in repository${NC}"
        echo -e "${RED}   Possible causes:${NC}"
        echo -e "${RED}   • Typo in branch name${NC}"
        echo -e "${RED}   • Branch was deleted or not yet pushed${NC}"
        echo -e "${RED}   • Wrong repository (currently using: ${REPO_URL})${NC}"
        echo ""
        echo -e "${YELLOW}   📋 Available branches:${NC}"
        git ls-remote --heads origin | head -20 | sed 's/.*refs\/heads\//    /'
        exit 1
    fi
fi
echo -e "${GREEN}   ✅ origin/${SOURCE_BRANCH} exists${NC}"

# Verify TARGET_BRANCH exists
echo -e "${YELLOW}🔍 Verifying target branch exists: ${TARGET_BRANCH}${NC}"
if ! git rev-parse --verify "origin/${TARGET_BRANCH}" >/dev/null 2>&1; then
    echo -e "${YELLOW}   ⏳ Branch not in shallow clone, fetching...${NC}"
    if ! git fetch origin "${TARGET_BRANCH}:refs/remotes/origin/${TARGET_BRANCH}" --depth=1 2>&1; then
        echo -e "${RED}❌ Error: Target branch '${TARGET_BRANCH}' does not exist in repository${NC}"
        echo -e "${RED}   Possible causes:${NC}"
        echo -e "${RED}   • Typo in branch name${NC}"
        echo -e "${RED}   • Branch was deleted or not yet created${NC}"
        echo -e "${RED}   • Wrong repository (currently using: ${REPO_URL})${NC}"
        echo ""
        echo -e "${YELLOW}   📋 Available branches:${NC}"
        git ls-remote --heads origin | head -20 | sed 's/.*refs\/heads\//    /'
        exit 1
    fi
fi
echo -e "${GREEN}   ✅ origin/${TARGET_BRANCH} exists${NC}"
echo ""

# Set up GitHub Actions environment variables
echo -e "${YELLOW}⚙️  Setting up environment variables${NC}"
export GITHUB_HEAD_REF="${SOURCE_BRANCH}"
export GITHUB_BASE_REF="${TARGET_BRANCH}"
export INPUT_WORKFLOW="${WORKFLOW}"
export INPUT_HOTFIX_PATTERN="hotfix/*"
export INPUT_FEATURE_PATTERN="feature/*"
export GITHUB_OUTPUT="/dev/stdout"

echo "  GITHUB_HEAD_REF=${GITHUB_HEAD_REF}"
echo "  GITHUB_BASE_REF=${GITHUB_BASE_REF}"
echo "  INPUT_WORKFLOW=${INPUT_WORKFLOW}"
echo "  INPUT_HOTFIX_PATTERN=${INPUT_HOTFIX_PATTERN}"
echo "  INPUT_FEATURE_PATTERN=${INPUT_FEATURE_PATTERN}"
echo ""

# Run the entrypoint script (replacing /github/workspace with test directory)
echo -e "${YELLOW}🚀 Running entrypoint.sh${NC}"
echo "────────────────────────────────────────"

# Create a modified version of the script for local testing
# Using @ as sed delimiter to avoid issues if TEST_DIR contains special characters
TEMP_SCRIPT=$(mktemp)
sed "s@/github/workspace@${TEST_DIR}@g" "${ENTRYPOINT_SCRIPT}" > "${TEMP_SCRIPT}"
chmod +x "${TEMP_SCRIPT}"

# Run the script and capture exit code
set +e
bash "${TEMP_SCRIPT}"
EXIT_CODE=$?
set -e

echo "────────────────────────────────────────"
echo ""

# Clean up temp script
rm -f "${TEMP_SCRIPT}"

# Report result
if [ ${EXIT_CODE} -eq 0 ]; then
    echo -e "${GREEN}🎉 Test PASSED (exit code: ${EXIT_CODE})${NC}"
else
    echo -e "${RED}💥 Test FAILED (exit code: ${EXIT_CODE})${NC}"
fi

# Optional: Clean up test directory
# rm -rf "${TEST_DIR}"

exit ${EXIT_CODE}
