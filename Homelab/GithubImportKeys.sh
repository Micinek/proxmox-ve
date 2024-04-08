#!/bin/bash

echo "Write your Github Username from which you want to import keys:"

# GitHub username to fetch keys
read GITHUB_USER

# Check if sudo is present
if command -v sudo &>/dev/null; then
    # Use sudo
    SUDO_CMD="sudo"
else
    # Run without sudo
    SUDO_CMD=""
    echo "Warning: sudo is not installed. Running without elevated privileges."
fi

# Check if curl is present, if not, attempt to install it
if ! command -v curl &>/dev/null; then
    echo "curl is not installed. Attempting to install..."

    # Check if the system has a default package manager (apt, yum, dnf, zypper)
    if command -v apt-get &>/dev/null; then
        $SUDO_CMD apt-get update
        $SUDO_CMD apt-get install -y curl
    elif command -v yum &>/dev/null; then
        $SUDO_CMD yum install -y curl
    elif command -v dnf &>/dev/null; then
        $SUDO_CMD dnf install -y curl
    elif command -v zypper &>/dev/null; then
        $SUDO_CMD zypper install -y curl
    else
        echo "Error: curl is required, but the installation method is not implemented for this distribution."
        exit 1
    fi
fi

# Path to the SSH directory
SSH_DIR="$HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# Check if the SSH directory exists
if [ ! -d "$SSH_DIR" ]; then
    mkdir "$SSH_DIR"
fi

# Check if authorized_keys file exists
if [ ! -f "$AUTHORIZED_KEYS" ]; then
    touch "$AUTHORIZED_KEYS"
fi

# Function to check if a key is present in authorized_keys
is_key_present() {
    local key_to_check="$1"
    grep -qF "$key_to_check" "$AUTHORIZED_KEYS"
}

# Function to import SSH keys
import_keys() {
    local github_keys
    github_keys=$(curl -s "https://github.com/$GITHUB_USER.keys")

    # Import keys
    local imported_keys=0
    local existing_keys=0

    while IFS= read -r key; do
        if ! is_key_present "$key"; then
            echo "$key" >> "$AUTHORIZED_KEYS"
            ((imported_keys++))
        else
            ((existing_keys++))
        fi
    done <<< "$github_keys"

    echo "Imported $imported_keys new key(s)"
    echo "Skipped $existing_keys existing key(s)"
}

# Run the import_keys function
import_keys
