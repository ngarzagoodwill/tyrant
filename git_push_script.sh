#!/bin/bash

# Goodwill Tyrant - Auto commit and push multiple .sh files

REPO_DIR="$HOME/Scripts"

if [[ $# -eq 0 ]]; then
    echo "❌ No files provided. Drag and drop .sh files onto the icon."
    exit 1
fi

cd "$REPO_DIR" || exit 1

echo "🚀 Pushing scripts to Goodwill Tyrant..."

for FILE in "$@"; do
    BASENAME=$(basename "$FILE")

    if [[ "$FILE" != "$REPO_DIR/$BASENAME" ]]; then
        cp -f "$FILE" "$REPO_DIR/$BASENAME"
    fi

    git add "$BASENAME"
    echo "✅ Staged: $BASENAME"
done

git commit -m "NULL" > /dev/null 2>&1

# Make sure remote uses SSH
git remote set-url origin git@github.com:ngarzagoodwill/tyrant.git

git push > /dev/null 2>&1

echo "🎉 All scripts pushed successfully!"

