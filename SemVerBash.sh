#!/bin/bash

# This function determines the release type based on a commit message.
# It simplifies the message for handling special characters and emojis.
# Based on semantic-release default release rules defined in:
# https://github.com/semantic-release/commit-analyzer/blob/master/lib/default-release-rules.js
determine_release_type() {
  local commit_message="$1"
  local release_type="none"

  # Simplify the commit message to handle emojis and other special characters
  # This transformation is necessary to match the simplified representation
  # of emojis used as keywords in commit messages.
  commit_message=$(echo "$commit_message" | sed 's/:racehorse:/racehorse/g; s/:bug:/bug/g; s/:penguin:/penguin/g; s/:apple:/apple/g; s/:checkered_flag:/checkered_flag/g')

  # Use a case statement to determine the release type based on commit message content.
  # The rules applied here are derived from the default release rules of semantic-release.
  case "$commit_message" in
    *breaking*|*Breaking*)
      release_type="major"
      ;;
    *revert*|*Revert*)
      release_type="patch"
      ;;
    *feat*|*FEAT*)
      release_type="minor"
      ;;
    *fix*|*FIX*|*bug*|*BUGFIX*|*perf*|*Perf*|*deps*|*Deps*|*racehorse*|*penguin*|*apple*|*checkered_flag*)
      release_type="patch"
      ;;
    *FEATURE*|*Update*|*New*)
      release_type="minor"
      ;;
    *SECURITY*)
      release_type="patch"
      ;;
    *)
      release_type="none"
      ;;
  esac

  echo "$release_type"
}

# Function to get the last tagged version that follows semantic versioning
get_last_tag() {
  # Use git tag with a regex pattern to list tags that match semantic versioning
  local tags=$(git tag --list --sort=-v:refname 'v?[0-9]*.[0-9]*.[0-9]*')

  # Get the latest tag that matches the semantic versioning pattern
  local last_semver_tag=$(echo "${tags}" | head -n 1)

  if [ -z "$last_semver_tag" ]; then
    # If no tags match the pattern, return a default version
    echo "0.0.0"
  else
    # Return the latest tag that matches semantic versioning
    echo "$last_semver_tag"
  fi
}

# Function to determine the version increment level based on commit messages
determine_version_increment() {
  local last_tag=$(get_last_tag)
  local commits

  if [ "$last_tag" = "0.0.0" ]; then
    # If no version tags are found, consider all commits
    commits=$(git log --oneline)
  else
    # If a last version tag is found, get commits from that tag to HEAD
    commits=$(git log ${last_tag}..HEAD --oneline)
  fi

  local increment="patch" # Default increment

  while IFS= read -r line; do
    local commit_type=$(determine_release_type "$line")
    if [[ "$commit_type" == "major" ]]; then
      increment="major"
      break
    elif [[ "$commit_type" == "minor" && "$increment" != "major" ]]; then
      increment="minor"
    fi
  done <<< "$commits"

  echo "$increment"
}


# Function to calculate the next version
calculate_next_version() {
    local last_version=$(get_last_tag | sed 's/^v//')  # Assuming tags are like v1.2.3
    if [[ $last_version == "" ]]; then
        last_version="0.0.0"
    fi

    local increment=$(determine_version_increment)
    IFS='.' read -r -a version_parts <<< "$last_version"
    local major=${version_parts[0]}
    local minor=${version_parts[1]}
    local patch=${version_parts[2]}

    case "$increment" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            # If no increment is needed, we will still bump the patch to avoid tag conflicts.
            patch=$((patch + 1))
            ;;
    esac

    local new_version="v${major}.${minor}.${patch}"

    # Check if the calculated version tag already exists and increment the patch number until it doesn't.
    while git rev-parse "$new_version" >/dev/null 2>&1; do
        patch=$((patch + 1))
        new_version="v${major}.${minor}.${patch}"
    done

    echo "$new_version"
}

# Function to create a new git tag for the next version
create_git_tag() {
  local next_version=$(calculate_next_version)
  git tag -a "v${next_version}" -m "Release v${next_version}"
  echo "Created new git tag: v${next_version}"
}

# Function to generate a formatted changelog since the last version
generate_structured_changelog() {
    local CHANGELOG_FILE="CHANGELOG.md"

    # Get the GitHub repository URL from GITHUB_REPOSITORY environment variable
    local REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

    # Initialize or clear the changelog file
    echo "# Change Log" > $CHANGELOG_FILE
    echo "" >> $CHANGELOG_FILE
    echo "All notable changes to this project will be documented in this file." >> $CHANGELOG_FILE
    echo "" >> $CHANGELOG_FILE

    # Ensure git fetches the tags and sets them up correctly
    git fetch --tags

    local previous_tag=""
    local tags=$(git tag --sort=-version:refname)
    for tag in $tags; do
        local tag_date=$(git log -1 --format=%ai $tag | cut -d ' ' -f1)
        echo "<a name=\"$tag\"></a>" >> $CHANGELOG_FILE
        echo "## [$tag](${REPO_URL}/releases/tag/$tag) ($tag_date)" >> $CHANGELOG_FILE
        echo "" >> $CHANGELOG_FILE

        local commits
        if [[ $previous_tag ]]; then
            commits=$(git log $previous_tag..$tag --pretty=format:"%s" --reverse)
        else
            commits=$(git log $tag --pretty=format:"%s" --reverse)
        fi

        local FEATURES=""
        local FIXES=""
        local OTHERS=""

        while IFS= read -r commit; do
            case "$commit" in
                feat:* )
                    FEATURES+="* $commit\n"
                    ;;
                fix:* )
                    FIXES+="* $commit\n"
                    ;;
                * )
                    OTHERS+="* $commit\n"
                    ;;
            esac
        done <<< "$commits"

        if [ ! -z "$FEATURES" ]; then
            echo "### Features" >> $CHANGELOG_FILE
            echo -e "$FEATURES" >> $CHANGELOG_FILE
        fi

        if [ ! -z "$FIXES" ]; then
            echo "### Bug Fixes" >> $CHANGELOG_FILE
            echo -e "$FIXES" >> $CHANGELOG_FILE
        fi

        if [ ! -z "$OTHERS" ]; then
            echo "### Other" >> $CHANGELOG_FILE
            echo -e "$OTHERS" >> $CHANGELOG_FILE
        fi

        echo "" >> $CHANGELOG_FILE

        previous_tag=$tag
    done

    cat $CHANGELOG_FILE > temp.md && mv temp.md $CHANGELOG_FILE
    cat $CHANGELOG_FILE
}

# Ensure GITHUB_REPOSITORY is available
if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GITHUB_REPOSITORY environment variable is not set."
    exit 1
fi

generate_structured_changelog_and_backup() {
    local CHANGELOG_FILE="CHANGELOG.md"
    local BACKUP_FILE="CHANGELOG.md-back"
    local REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

    # Aquí iría la implementación de la generación del changelog como se discutió anteriormente.
    # Omitido por brevedad, asumiendo que ya está definido en este punto del script.

    # Backup the previous changelog
    if [ -f "$CHANGELOG_FILE" ]; then
        cp "$CHANGELOG_FILE" "$BACKUP_FILE"
    fi

    # Generate the new changelog
    generate_structured_changelog

    # Add and commit changes
    git add "$CHANGELOG_FILE" "$BACKUP_FILE"
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local new_version_tag=$(git describe --tags `git rev-list --tags --max-count=1`)
    
    # Commit the changes
    git commit -m "Update changelog for $new_version_tag"

    # Calculating next version
    next_version=$(calculate_next_version)
    # Tag the new version
    git tag -a "$next_version" -m "Release $new_version_tag"

    # Push changes and tags
    git push origin "$current_branch"
    git push origin "$new_version_tag"
}

# Example usage
commit_message="feat: add new feature"
release_type=$(determine_release_type "$commit_message")
echo "Commit message: '$commit_message' results in a release type of: $release_type"

# Example usage
next_version=$(calculate_next_version)
echo "Next version: $next_version"

# Example usage
next_version=$(calculate_next_version)
generate_structured_changelog_and_backup
