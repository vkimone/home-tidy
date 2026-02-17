#!/bin/bash
# =========================================================
# Release Helper Script for home-tidy
# =========================================================
# Usage: ./scripts/release.sh <major|minor|patch|version>
# Example:
#   ./scripts/release.sh patch    # 0.1.0 -> 0.1.1
#   ./scripts/release.sh minor    # 0.1.0 -> 0.2.0
#   ./scripts/release.sh major    # 0.1.0 -> 1.0.0
#   ./scripts/release.sh 1.2.3    # Set to specific version
# =========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "❌ VERSION file not found at $VERSION_FILE"
    exit 1
fi

CURRENT_VERSION=$(cat "$VERSION_FILE")

if [[ -z "$1" ]]; then
    echo "Usage: $0 <major|minor|patch|version>"
    echo "Current version: $CURRENT_VERSION"
    exit 1
fi

# Parse current version
IFS='.' read -r -a version_parts <<< "$CURRENT_VERSION"
MAJOR="${version_parts[0]}"
MINOR="${version_parts[1]}"
PATCH="${version_parts[2]}"

# Determine new version
case "$1" in
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    [0-9]*.[0-9]*.[0-9]*)
        NEW_VERSION="$1"
        ;;
    *)
        echo "❌ Invalid argument: $1"
        echo "Usage: $0 <major|minor|patch|version>"
        exit 1
        ;;
esac

echo "📦 Current version: $CURRENT_VERSION"
echo "🆕 New version: $NEW_VERSION"
echo ""

# Confirm
read -p "Continue with version bump? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Release cancelled"
    exit 0
fi

# Update VERSION file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "✅ Updated VERSION file to $NEW_VERSION"

# Git operations (if in git repo)
if git rev-parse --git-dir > /dev/null 2>&1; then
    # Check for uncommitted changes
    if [[ -n $(git status -s) ]]; then
        echo ""
        echo "📝 Staging changes..."
        git add "$VERSION_FILE"
        
        # Ask if user wants to commit other changes too
        if [[ $(git status -s | wc -l) -gt 1 ]]; then
            echo ""
            git status -s
            echo ""
            read -p "Stage all changes for release commit? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git add .
            fi
        fi
        
        # Commit
        git commit -m "chore: bump version to $NEW_VERSION"
        echo "✅ Created release commit"
    fi
    
    # Create tag
    echo ""
    read -p "Create git tag v$NEW_VERSION? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -a "v$NEW_VERSION" -m "Release version $NEW_VERSION"
        echo "✅ Created tag v$NEW_VERSION"
        echo ""
        echo "📌 To push the tag to remote, run:"
        echo "   git push origin v$NEW_VERSION"
        echo "   git push origin main"
    fi
else
    echo "⚠️  Not a git repository, skipping git operations"
fi

echo ""
echo "✨ Release preparation complete!"
echo "   Version: $NEW_VERSION"
