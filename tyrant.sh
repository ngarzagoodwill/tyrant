#!/bin/bash

# 🏠 Determine real user's home directory even when running with sudo
if [ "$EUID" -eq 0 ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
else
    USER_HOME="$HOME"
fi

LOG_FILE="$USER_HOME/.tyrant_update.log"

echo "🦾 Welcome to Goodwill Tyrant Script Launcher"
echo "🔍 Checking for script updates..."

REPO_DIR="$USER_HOME/Scripts"
HASH_DIR="$USER_HOME/.tyrant_hashes"
GIT_CONFIG_FILE="$REPO_DIR/usrinfo/gitconfig.txt"

# 🔐 Get Git remote URL
if [[ ! -f "$GIT_CONFIG_FILE" ]]; then
    echo "❌ Git remote config file not found at $GIT_CONFIG_FILE"
    exit 1
fi

GIT_REMOTE=$(<"$GIT_CONFIG_FILE")

mkdir -p "$HASH_DIR"

# 🔄 Pull latest repo updates
if [ "$EUID" -eq 0 ]; then
    sudo -u "$SUDO_USER" git -C "$REPO_DIR" remote set-url origin "$GIT_REMOTE"
    sudo -u "$SUDO_USER" git -C "$REPO_DIR" pull --quiet || { echo "❌ Git pull failed."; exit 1; }
else
    cd "$REPO_DIR" || { echo "❌ Cannot find $REPO_DIR directory."; exit 1; }
    git remote set-url origin "$GIT_REMOTE"
    git pull --quiet || { echo "❌ Git pull failed."; exit 1; }
fi

UPDATED_FILES=()

# 🔍 Check for updated .sh files using hash comparison
for FILE in "$REPO_DIR"/*.sh; do
    BASENAME=$(basename "$FILE")
    HASH_FILE="$HASH_DIR/$BASENAME.hash"
    NEW_HASH=$(sha256sum "$FILE" | awk '{print $1}')

    if [[ ! -f "$HASH_FILE" ]] || [[ "$NEW_HASH" != "$(cat "$HASH_FILE")" ]]; then
        echo "$NEW_HASH" > "$HASH_FILE"
        UPDATED_FILES+=("$BASENAME")
    fi
done

# 📦 Auto-commit and push any changed .sh files
if [[ ${#UPDATED_FILES[@]} -gt 0 ]]; then
    echo "⬇️  Updated scripts pulled or modified locally:"
    for f in "${UPDATED_FILES[@]}"; do
        echo "   - $f"
        git -C "$REPO_DIR" add "$f"
    done

    echo "💾 Committing changes..."
    git -C "$REPO_DIR" commit -m "Auto-update via Tyrant" >/dev/null 2>&1

    echo "🚀 Pushing to remote..."
    if git -C "$REPO_DIR" push >/dev/null 2>&1; then
        echo "✅ Push successful."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Pushed updates: ${UPDATED_FILES[*]}" >> "$LOG_FILE"
    else
        echo "❌ Push failed! Please check your SSH key or network connection."
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Push failed for updates: ${UPDATED_FILES[*]}" >> "$LOG_FILE"
    fi
else
    echo "✅ No script updates found."
fi

# 📋 Show menu
echo ""
echo "📋 Choose an action:"
echo "1) Check Drive Health"
echo "2) Wipe A Drive"
echo "3) Dump Data"
echo "4) Specs Sheet"
echo "0) Exit"
echo ""

read -rp "➡️  Enter choice [0-4]: " choice

SCRIPTS_DIR="$REPO_DIR"

case "$choice" in
    1) bash "$SCRIPTS_DIR/check_drive_health.sh" ;;
    2) bash "$SCRIPTS_DIR/safe_erase.sh" ;;
    3) bash "$SCRIPTS_DIR/hexdump_sda.sh" ;;
    4) sudo bash "$SCRIPTS_DIR/deepdivehardware.sh" && bash "$SCRIPTS_DIR/newsalesreport.sh" ;;
    0) echo "👋 Goodbye!" && exit 0 ;;
    *) echo "❌ Invalid choice." && exit 1 ;;
esac

