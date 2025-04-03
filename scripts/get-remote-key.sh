#!/bin/bash

# Help function
show_help() {
    echo "Usage: $0 [options] [user@]hostname"
    echo
    echo "Options:"
    echo "  -p PORT     Specify SSH port (default: 22)"
    echo "  -i IDENTITY Use specific identity file for SSH connection"
    echo "  -t TYPE     Key type to retrieve (default: ed25519, can be rsa, ecdsa, etc.)"
    echo "  -h          Display this help and exit"
    echo
    echo "Example:"
    echo "  $0 -p 2222 -t rsa root@example.com"
}

# Default values
PORT=22
KEY_TYPE="ed25519"
IDENTITY=""

# Parse options
while getopts "p:i:t:h" opt; do
    case $opt in
        p) PORT="$OPTARG" ;;
        i) IDENTITY="-i $OPTARG" ;;
        t) KEY_TYPE="$OPTARG" ;;
        h) show_help; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; show_help; exit 1 ;;
    esac
done

# Remove options from argument list
shift $((OPTIND-1))

# Check if hostname is provided
if [ $# -ne 1 ]; then
    echo "Error: Missing hostname" >&2
    show_help
    exit 1
fi

# Extract username and hostname
REMOTE_HOST="$1"
if [[ "$REMOTE_HOST" != *"@"* ]]; then
    # If no username provided, use current user
    REMOTE_HOST="$(whoami)@$REMOTE_HOST"
fi

# Extract just the hostname part for the key output
HOSTNAME=$(echo "$REMOTE_HOST" | cut -d@ -f2)
USERNAME=$(echo "$REMOTE_HOST" | cut -d@ -f1)

# Command to execute on remote host to get the key
REMOTE_CMD="cat ~/.ssh/id_${KEY_TYPE}.pub 2>/dev/null || cat /etc/ssh/ssh_host_${KEY_TYPE}_key.pub 2>/dev/null"

# Get the SSH key
echo "Retrieving $KEY_TYPE SSH key from $REMOTE_HOST..." >&2
SSH_KEY=$(ssh $IDENTITY -p "$PORT" "$REMOTE_HOST" "$REMOTE_CMD")

if [ -z "$SSH_KEY" ]; then
    echo "Error: Could not retrieve $KEY_TYPE SSH key from $REMOTE_HOST" >&2
    exit 1
fi

# Format the key in the requested format
FORMATTED_KEY=$(echo "$SSH_KEY" | awk '{print $1, $2}')
echo "$FORMATTED_KEY $USERNAME@$HOSTNAME"
