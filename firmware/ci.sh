#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Embassy Template CI Test Script ==="
echo ""

# Check if cargo-generate is installed, install if not
if ! command -v cargo-generate &> /dev/null; then
    echo -e "${YELLOW}cargo-generate not found. Installing...${NC}"
    cargo install cargo-generate
else
    echo -e "${GREEN}cargo-generate is already installed${NC}"
fi

# Array of chips to test
CHIPS=(
    "nrf52840"
    "nrf54l15"
    "nrf9160"
    "rp2040"
    "rp2350a"
    # Below are some auto-generated chips
    "stm32h743zi"
    "stm32l053r8"
    "stm32f373c8"
)

# Get the absolute path to the template directory
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create a temporary directory for testing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${YELLOW}Testing template generation in: $TEMP_DIR${NC}"
echo ""

# Counter for success/failure
PASSED=0
FAILED=0
FAILED_CHIPS=()

# Test each chip
for CHIP in "${CHIPS[@]}"; do
    echo "========================================="
    echo -e "${YELLOW}Testing chip: $CHIP${NC}"
    echo "========================================="

    PROJECT_NAME="test-${CHIP}"
    PROJECT_DIR="$TEMP_DIR/$PROJECT_NAME"

    # Generate project from template
    echo "Generating project..."
    if (cd "$TEMP_DIR" && cargo generate --path "$TEMPLATE_DIR" \
        --name "$PROJECT_NAME" \
        -d chip="$CHIP" \
        -d authors="CI Test" \
        --silent); then
        echo -e "${GREEN}✓ Project generated successfully${NC}"
    else
        echo -e "${RED}✗ Failed to generate project${NC}"
        FAILED=$((FAILED + 1))
        FAILED_CHIPS+=("$CHIP (generation)")
        continue
    fi

    # Build the generated project
    echo "Building project with cargo build --release..."
    if (cd "$PROJECT_DIR" && cargo build --release 2>&1); then
        echo -e "${GREEN}✓ Build successful for $CHIP${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ Build failed for $CHIP${NC}"
        FAILED=$((FAILED + 1))
        FAILED_CHIPS+=("$CHIP (build)")
    fi

    echo ""
done

# Print summary
echo "========================================="
echo "SUMMARY"
echo "========================================="
echo -e "Total chips tested: ${#CHIPS[@]}"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed chips:${NC}"
    for CHIP in "${FAILED_CHIPS[@]}"; do
        echo -e "  - $CHIP"
    done
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
fi
