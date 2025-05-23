#!/bin/bash

# This script symlinks the common configuration files and then
# symlinks OS-specific configuration files based on the argument provided.

# Define the path to your dotfiles directory
DOTFILES_DIR="$HOME/dotfiles/" # Update this with the actual path to your dotfiles
TARGET_DIR="$HOME"             # The target directory for symlinks, usually the home directory

# Check for correct argument usage
if [ $# -ne 1 ]; then
	echo "Usage: $0 <os_type>"
	echo "Where <os_type> is 'macos' or 'linux'"
	exit 1
fi

OS_TYPE=$1

# Validate OS_TYPE argument
if [[ "$OS_TYPE" != "macos" && "$OS_TYPE" != "linux" ]]; then
	echo "Error: Unsupported OS type '$OS_TYPE'. Use 'macos' or 'linux'."
	exit 1
fi

# Navigate to the dotfiles directory
cd "$DOTFILES_DIR" || {
	echo "Error: Failed to change directory to $DOTFILES_DIR"
	exit 1
}

# Stow common files first
stow common -t "$TARGET_DIR"
echo "Common configuration files have been symlinked."

# Stow OS-specific files based on the argument
stow "$OS_TYPE" -t "$TARGET_DIR"
echo "$OS_TYPE configuration files have been symlinked."

echo "Symlinking process completed."
