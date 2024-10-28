#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Print each command before executing it.
set -x

# Ensure required environment variables are set
: "${INPUT_PACKAGES:?Environment variable INPUT_PACKAGES is not set}"
: "${INPUT_MISSING_AUR_DEPENDENCIES:?Environment variable INPUT_MISSING_AUR_DEPENDENCIES is not set}"

# Combine AUR packages and their missing AUR dependencies
packages_with_aur_dependencies="$INPUT_PACKAGES $INPUT_MISSING_AUR_DEPENDENCIES"

echo "AUR Packages requested to install: $INPUT_PACKAGES"
echo "AUR Packages to fix missing dependencies: $INPUT_MISSING_AUR_DEPENDENCIES"
echo "AUR Packages to install (including dependencies): $packages_with_aur_dependencies"

# Update the package database and upgrade all packages
sudo pacman -Syu --noconfirm

# Install pacman-contrib for repo-add if not already installed
if ! pacman -Qi pacman-contrib > /dev/null 2>&1; then
    sudo pacman -S --noconfirm pacman-contrib
fi

git clone https://aur.archlinux.org/yay-bin.git && \
    cd yay-bin && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay-bin

# Install any additional missing Pacman dependencies, if specified
if [ -n "$INPUT_MISSING_PACMAN_DEPENDENCIES" ]; then
    echo "Additional Pacman packages to install: $INPUT_MISSING_PACMAN_DEPENDENCIES"
    sudo pacman --noconfirm -S $INPUT_MISSING_PACMAN_DEPENDENCIES
fi

# Define the build directory and repository name
BUILD_DIR="/home/builder/workspace"
REPO_NAME="aurci2"
DB_FILE="${BUILD_DIR}/${REPO_NAME}.db.tar.gz"
FILES_FILE="${BUILD_DIR}/${REPO_NAME}.files.tar.gz"

# Ensure the build directory exists and has correct permissions
sudo mkdir -p "$BUILD_DIR"
sudo chown builder:builder "$BUILD_DIR"

# Use yay to build the AUR packages without installing them
# --noconfirm: Do not ask for confirmation
# --nodiffmenu and --nodiffview: Do not show diff or view menus
# --noeditmenu: Do not show the edit menu
# --builddir: Specify the build directory
# --needed: Skip already installed packages
# --mflags "--nocheck": Skip running checks; adjust as needed
sudo -u builder yay -S --noconfirm \
    --nodiffmenu \
    --nodiffview \
    --noeditmenu \
    --builddir "$BUILD_DIR" \
    --needed \
    --mflags "--nocheck" \
    $packages_with_aur_dependencies

# Navigate to the build directory
cd "$BUILD_DIR"

# Create or update the repository database
if [ -f "$DB_FILE" ] && [ -f "$FILES_FILE" ]; then
    echo "Updating existing repository database..."
    repo-add "$REPO_NAME".db.tar.gz *.pkg.tar.zst
else
    echo "Creating new repository database..."
    repo-add "$REPO_NAME".db.tar.gz *.pkg.tar.zst
fi

# Compress the database files
gzip -c "$REPO_NAME".db > "$REPO_NAME".db.tar.gz
gzip -c "$REPO_NAME".files > "$REPO_NAME".files.tar.gz

# Move the local repository to the GitHub workspace, if defined
if [ -n "$GITHUB_WORKSPACE" ]; then
    echo "Cleaning up old repository files..."
    rm -f "${BUILD_DIR}"/*.old

    echo "Moving repository to GitHub workspace..."
    mv "${BUILD_DIR}"/* "$GITHUB_WORKSPACE/"

    # Ensure that the .db and .files databases are properly copied
    # Symlinks might fail to upload, so copy the actual files
    cd "$GITHUB_WORKSPACE"
    rm -f "${REPO_NAME}.db" "${REPO_NAME}.files"
    cp "${REPO_NAME}.db.tar.gz" "${REPO_NAME}.db"
    cp "${REPO_NAME}.files.tar.gz" "${REPO_NAME}.files"
else
    echo "No GitHub workspace detected (GITHUB_WORKSPACE is unset)."
fi

echo "AUR packages have been successfully built and the repository has been updated."
