#!/bin/bash

# Add logging definition to make output clearer
## Info
LOGI() {
    echo -e "[\033[32mINFO\033[0m]: ${1}"
}

## Warning
LOGW() {
    echo -e "[\033[33mWARNING\033[0m]: ${1}"
}

## Error
LOGE() {
    echo -e "[\033[31mERROR\033[0m]: ${1}"
}

## Fatal
LOGF() {
    echo -e "[\033[41mFATAL\033[0m]: ${1}"
    exit 1
}

# Determine which command to use for privilege escalation
if command -v sudo > /dev/null 2>&1; then
    sudo_cmd="sudo"
elif command -v doas > /dev/null 2>&1; then
    sudo_cmd="doas"
else
    LOGW "Neither 'sudo' nor 'doas' found; resorting to 'su'."
    # Create a separated function in order to handle 'su'
    su_cmd() { 
        su -c "$*" 
    }
    sudo_cmd="su_cmd"
fi

# 'apt' (Debian)
if command -v apt > /dev/null 2>&1; then
    # Perform repositories updates to prevent dead mirrors
    LOGI "Updating repositories..."
    $sudo_cmd apt update > /dev/null 2>&1

    # Install required packages in form of a 'for' loop
    for package in unace unrar zip unzip p7zip-full p7zip-rar sharutils rar uudeview mpack arj cabextract device-tree-compiler liblzma-dev python3-pip brotli liblz4-tool axel gawk aria2 detox cpio rename liblz4-dev curl ripgrep; do
        LOGI "Installing '${package}'..."
        if ! $sudo_cmd apt install  -y "${package}" > /dev/null 2>&1; then
            LOGE "Failed installing '${package}'."
            case ${package} in
                liblz4-tool)
                    $sudo_cmd apt install lz4 -y > /dev/null 2>&1 || \
                        LOGE "Failed installing 'lz4'."
                ;;
            esac
        fi
    done
# 'dnf' (Fedora)
elif command -v dnf > /dev/null 2>&1; then
    # Install required packages in form of a 'for' loop
    for package in unace unrar zip unzip sharutils uudeview arj cabextract file-roller dtc python3-pip brotli axel aria2 detox cpio lz4 python3-devel xz-devel p7zip p7zip-plugins ripgrep; do
        LOGI "Installing '${package}'..."
        $sudo_cmd dnf install -y "${package}" > /dev/null 2>&1 || \
            LOGE "Failed installing '${package}'."
    done
# 'pacman' (Arch Linux)
elif command -v pacman > /dev/null 2>&1; then
    # Install required packages in form of a 'for' loop
    for package in unace unrar zip unzip p7zip sharutils uudeview arj cabextract file-roller dtc python-pip brotli axel gawk aria2 detox cpio lz4 ripgrep; do
        LOGI "Installing '${package}'..."
        $sudo_cmd pacman -Sy --noconfirm --needed "${package}" > /dev/null 2>&1 || \
            LOGE "Failed installing '${package}'."
    done
fi

# --- Install Latest 7-Zip (7zz) from GitHub ---
# The standard repo version of 7zip might be old, so we fetch the latest release binary
LOGI "Checking for latest 7-Zip (7zz) from GitHub..."

# Create a temporary directory for download operations
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1

# Set repository and API URL to fetch the latest release information
REPO="ip7z/7zip"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

LOGI "Fetching latest release info for ${REPO}..."

# Fetch the JSON data and parse the download URL for the linux-x64 tarball
# Prefer curl, but fallback to wget if curl is not available
if command -v curl > /dev/null 2>&1; then
    # Use grep and sed to extract the browser_download_url matching linux-x64.tar.xz
    DOWNLOAD_URL=$(curl -s "$API_URL" | \
      grep -o '"browser_download_url": *"https://[^"]*linux-x64.tar.xz"' | \
      sed 's/.*"browser_download_url": *"//;s/"$//')
elif command -v wget > /dev/null 2>&1; then
    # Fallback to wget if curl is missing
    DOWNLOAD_URL=$(wget -qO- "$API_URL" | \
      grep -o '"browser_download_url": *"https://[^"]*linux-x64.tar.xz"' | \
      sed 's/.*"browser_download_url": *"//;s/"$//')
else
    LOGE "Neither curl nor wget found. Cannot fetch 7-Zip from GitHub."
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    exit 1
fi

# Check if the URL extraction was successful
if [ -z "$DOWNLOAD_URL" ]; then
    LOGE "Failed to find 'linux-x64.tar.xz' download URL for 7-Zip."
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    exit 1
fi

LOGI "Latest 7-Zip Linux x64 URL: ${DOWNLOAD_URL}"

# Download the tarball
LOGI "Downloading 7-Zip linux-x64 tarball..."
if command -v wget > /dev/null 2>&1; then
    wget -q "$DOWNLOAD_URL" -O 7zz.tar.xz
elif command -v curl > /dev/null 2>&1; then
    curl -sL "$DOWNLOAD_URL" -o 7zz.tar.xz
else
    LOGE "Neither wget nor curl available. Cannot download 7zz."
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    exit 1
fi

# Verify that the download completed
if [ ! -f "7zz.tar.xz" ]; then
    LOGE "Failed to download 7zz tarball."
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract the downloaded archive
LOGI "Extracting 7zz tarball..."
tar -xf 7zz.tar.xz

# Check if the binary exists in the extracted content
if [ ! -f "7zz" ]; then
    LOGE "The archive does not contain '7zz' binary."
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    exit 1
fi

# Install the binary to /usr/local/bin/7zz
$sudo_cmd install -m 755 7zz /usr/local/bin/7zz
LOGI "Installed 7zz to /usr/local/bin/7zz."

# --- Symlink creation REMOVED as per request ---
# We keep the system's /usr/bin/7z (p7zip) and 7zz separately.

# Return to the original directory and clean up the temporary files
cd - > /dev/null
rm -rf "$TMP_DIR"

# Verify that the installation was successful and 7zz is in the PATH
if command -v 7zz > /dev/null 2>&1; then
    LOGI "Verifying installation: 7zz version:"
    7zz
else
    LOGE "7zz still not found after installation."
fi

# Install 'uv' through pipx
LOGI "Installing 'uv'..."
curl -LsSf https://astral.sh/uv/install.sh | sh > /dev/null 2>&1 

# Install aospdtgen
LOGI "Installing 'aospdtgen'..."
pip3 install aospdtgen || LOGE "Failed to install 'aospdtgen'."

# Finish
LOGI "Set-up finished. You may now execute 'dumpyara.sh'."
