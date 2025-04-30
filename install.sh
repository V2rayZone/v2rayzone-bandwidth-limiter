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
DEFAULT_VERSION="latest"

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

prompt_version() {
    echo -e "${YELLOW}Enter version to install (e.g., v1.0, latest):${PLAIN}"
    read -r VERSION_INPUT

    if [[ -z "$VERSION_INPUT" ]]; then
        VERSION="latest"
        echo -e "${GREEN}Using latest version...${PLAIN}"
    else
        VERSION="$VERSION_INPUT"
        echo -e "${GREEN}Installing version: $VERSION...${PLAIN}"
    fi
}

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
    echo -e "${BLUE}Download URL: $DOWNLOAD_URL${PLAIN}"
}

download_zip() {
    echo -e "${YELLOW}Downloading version: $VERSION...${PLAIN}"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    curl -Ls "$DOWNLOAD_URL" -o "$INSTALL_DIR/v2rayzone-bandwidth-limiter.zip"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Download failed. Check internet connection or version exists.${PLAIN}"
        exit 1
    fi
}

extract_zip() {
    echo -e "${YELLOW}Extracting files...${PLAIN}"
    unzip "$INSTALL_DIR/v2rayzone-bandwidth-limiter.zip" -d "$INSTALL_DIR" > /dev/null

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to extract ZIP. Corrupted or invalid format?${PLAIN}"
        exit 1
    fi

    # Detect extracted subfolder
    extracted_dir=$(unzip -l "$INSTALL_DIR/v2rayzone-bandwidth-limiter.zip" | awk '/^dr/ {print $4}' | head -1)
    if [ -n "$extracted_dir" ] && [ -d "$INSTALL_DIR/$extracted_dir" ]; then
        mv "$INSTALL_DIR/$extracted_dir"/* "$INSTALL_DIR/"
        rmdir "$INSTALL_DIR/$extracted_dir"
    fi

    if [ ! -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        echo -e "${RED}ZIP does not contain expected script: $SCRIPT_NAME${PLAIN}"
        exit 1
    fi

    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
}

run_main_script() {
    echo -e "${GREEN}Starting bandwidth limiter setup...${PLAIN}"
    cd "$INSTALL_DIR" || { echo -e "${RED}Failed to enter install directory${PLAIN}"; exit 1; }
    "./$SCRIPT_NAME"
}

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

trap 'echo -e "\n${YELLOW}Installation cancelled by user.${PLAIN}"; exit 1' INT

check_dependencies
main_loop
