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

# Retrieves the last git tag that follows semantic versioning.
# If no semantic versioning tags are found, defaults to "0.0.0".
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

# Determines the version increment level based on commit messages
# from the last versioned tag to HEAD. Defaults to "patch", but can be adjusted
# based on the types of releases found in the commit messages.
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


# Calculates the next version based on the last versioned tag and the determined increment.
# It updates version numbers according to semantic versioning rules and ensures
# the new version does not already exist as a Git tag.
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

# Creates a new Git tag for the next version calculated by `calculate_next_version`.
# It then prints a confirmation message with the new tag.
create_git_tag() {
  local next_version=$(calculate_next_version)
  git tag -a "v${next_version}" -m "Release v${next_version}"
  echo "Created new git tag: v${next_version}"
}

# Generates a structured changelog documenting changes since the last versioned tag.
# The changelog is formatted in Markdown and includes links to the GitHub repository.
# This function relies on existing Git tags and commit messages to organize the changes.
generate_structured_changelog() {
    local CHANGELOG_FILE="CHANGELOG.md"
    local TEMP_CHANGELOG_FILE="TEMP_CHANGELOG.md"

    # Get the GitHub repository URL from GITHUB_REPOSITORY environment variable
    local REPO_URL="https://github.com/${GITHUB_REPOSITORY}"

    # Get the latest and previous tags
    local latest_tag=$(git describe --tags `git rev-list --tags --max-count=1`)
    local previous_tag=$(git describe --tags `git rev-list --tags --max-count=2` | sed -n '2p')

    # Initialize the temporary changelog file
    echo "# Changelog" > $TEMP_CHANGELOG_FILE
    echo "" >> $TEMP_CHANGELOG_FILE
    echo "All notable changes to this project will be documented in this file." >> $TEMP_CHANGELOG_FILE
    echo "" >> $TEMP_CHANGELOG_FILE

    local tag_date=$(git log -1 --format=%ai $latest_tag | cut -d ' ' -f1)
    echo "## [$latest_tag](${REPO_URL}/releases/tag/$latest_tag) - $tag_date" >> $TEMP_CHANGELOG_FILE
    echo "" >> $TEMP_CHANGELOG_FILE

    # Fetch commits between the latest and previous tags, or all if no previous tag
    local commits
    if [ -n "$previous_tag" ]; then
        commits=$(git log $previous_tag..$latest_tag --pretty=format:"* %s" --reverse)
    else
        commits=$(git log $latest_tag --pretty=format:"* %s" --reverse)
    fi

    if [ ! -z "$commits" ]; then
        echo "$commits" >> $TEMP_CHANGELOG_FILE
    else
        echo "* No significant changes." >> $TEMP_CHANGELOG_FILE
    fi

    echo "" >> $TEMP_CHANGELOG_FILE

    # If an existing changelog file exists, append it to the temporary file
    if [ -f "$CHANGELOG_FILE" ]; then
        cat $CHANGELOG_FILE >> $TEMP_CHANGELOG_FILE
    fi

    # Replace the old CHANGELOG.md with the new one
    mv $TEMP_CHANGELOG_FILE $CHANGELOG_FILE

    cat $CHANGELOG_FILE
}


# Ensure GITHUB_REPOSITORY is available
if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GITHUB_REPOSITORY environment variable is not set."
    exit 1
fi

# Extends `generate_structured_changelog` by also backing up the current changelog
# before generating a new one. It tracks changes in Git, tags the new version, and optionally
# updates the remote repository with these changes.
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
next_version=$(calculate_next_version)
echo "Next version: $next_version"

# Example usage
next_version=$(calculate_next_version)
generate_structured_changelog_and_backup
