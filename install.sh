#!/bin/bash

# V2RayZone Bandwidth Limiter Installer
# Author: V2RayZone

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# Constants
GITHUB_REPO="V2RayZone/v2rayzone-bandwidth-limiter"
INSTALL_DIR="/opt/v2rayzone-bandwidth-limiter"
SCRIPT_NAME="v2rayzone-bandwidth-limiter.sh"
LOG_FILE="/var/log/v2rayzone-installer.log"

echo -e "${BLUE}V2RayZone Bandwidth Limiter Installer${PLAIN}"

# Ensure required tools are installed
check_dependencies() {
    for tool in curl unzip; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${YELLOW}Installing $tool...${PLAIN}"
            apt-get update && apt-get install -y "$tool" || {
                echo -e "${RED}Failed to install $tool. Exiting.${PLAIN}"
                exit 1
            }
        fi
    done
}

# Prompt for version
prompt_version() {
    echo -e "${YELLOW}Enter version to install (e.g., v1.0, latest):${PLAIN}"
    read -r VERSION

    if [[ -z "$VERSION" ]]; then
        VERSION="latest"
        echo -e "${GREEN}Using latest version...${PLAIN}"
    else
        echo -e "${GREEN}Installing version: $VERSION...${PLAIN}"
    fi
}

# Get ZIP download URL
get_download_url() {
    if [[ "$VERSION" == "latest" ]]; then
        DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$GITHUB_REPO/releases/latest \
            | grep "browser_download_url.*zip" \
            | cut -d '"' -f 4)

        if [[ -z "$DOWNLOAD_URL" ]]; then
            echo -e "${RED}Failed to fetch latest release from GitHub API${PLAIN}"
            exit 1
        fi
    else
        DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/v2rayzone-bandwidth-limiter.zip"
    fi
}

# Download ZIP file
download_zip() {
    echo -e "${YELLOW}Downloading version: $VERSION...${PLAIN}"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    curl -Ls "$DOWNLOAD_URL" -o "$INSTALL_DIR/v2rayzone-bandwidth-limiter.zip"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Download failed. Check your internet or version exists.${PLAIN}"
        exit 1
    fi
}

# Extract ZIP file
extract_zip() {
    echo -e "${YELLOW}Extracting files...${PLAIN}"
    unzip "$INSTALL_DIR/v2rayzone-bandwidth-limiter.zip" -d "$INSTALL_DIR" > /dev/null

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to extract ZIP file. Corrupted or invalid format?${PLAIN}"
        exit 1
    fi

    if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        echo -e "${RED}ZIP does not contain expected script: $SCRIPT_NAME${PLAIN}"
        exit 1
    fi

    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
}

# Run the main script
run_main_script() {
    echo -e "${GREEN}Starting bandwidth limiter setup...${PLAIN}"
    cd "$INSTALL_DIR" || { echo -e "${RED}Failed to enter install directory${PLAIN}"; exit 1; }
    "./$SCRIPT_NAME"
}

# Main function using loop instead of recursion
main_loop() {
    while true; do
        clear
        echo -e "${BLUE}=== V2RayZone Installer ===${PLAIN}"
        echo -e "1. Install Bandwidth Limiter"
        echo -e "2. Exit"
        echo -e ""
        read -p "Select an option [1-2]: " choice

        case "$choice" in
            1)
                prompt_version
                get_download_url
                download_zip
                extract_zip
                run_main_script
                ;;
            2)
                echo -e "${GREEN}Exiting installer.${PLAIN}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid input. Please try again.${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# Start execution
trap 'echo -e "\n${YELLOW}Installation cancelled by user.${PLAIN}"; exit 1' INT

check_dependencies
main_loop
