# Automated Version Management and Changelog Generation

This Bash script automates version management and changelog generation for software projects, based on semantic versioning and Git commit messages.

## Features

- **Determines release type:** Evaluates commit messages to identify major, minor, or patch releases.
- **Calculates next version:** Automatically calculates the next software version based on commits since the last version.
- **Generates a structured changelog:** Creates a `CHANGELOG.md` file detailing all significant changes grouped by version.
- **Automates Git tags:** Automatically generates Git tags for new software versions.

## Prerequisites

To use this script, you must have `Git` installed on your system. Additionally, you need to set the `GITHUB_REPOSITORY` environment variable in the format `user/repository`.

## Configuration

Before running the script, make sure to correctly configure the `GITHUB_REPOSITORY` environment variable to match your GitHub repository.

```bash
export GITHUB_REPOSITORY="user/repository"
```

## Usage

To run the script, use the following command in the terminal:

```bash
bash script.sh
```

Ensure you are in your Git project directory and have previously set up the `GITHUB_REPOSITORY` variable.

## Key Functions

### `determine_release_type`

Determines the version type (major, minor, patch, none) based on analyzing the content of commit messages.

### `get_last_tag`

Fetches the last Git tag that follows the semantic versioning format, returning "0.0.0" if none are found.

### `determine_version_increment`

Sets the version increment level (major, minor, patch) based on commit messages from the last tagged version to `HEAD`.

### `calculate_next_version`

Calculates the next version of the software based on the last tag and the determined version increment.

### `create_git_tag`

Creates a new Git tag for the calculated version, with a confirmation message of creation.

### `generate_structured_changelog`

Generates a structured changelog with notable changes since the last version, recording them in a `CHANGELOG.md` file.

### `generate_structured_changelog_and_backup`

In addition to generating a structured changelog, this function backs up the existing changelog and automates the process of adding, committing, and tagging changes in the Git repository.

## Example Usage

To automatically calculate the next version and update the changelog:

```bash
./SemVerBash.sh
```

This command runs the script, which calculates the next version based on commits, generates a structured changelog, and updates the Git repository with a new tag.
