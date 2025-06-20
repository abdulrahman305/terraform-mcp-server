#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0


# The crt-build script is used to detemine build metadata and create terraform-mcp-server builds.
# We use it in build.yml for building release artifacts with CRT in the Go Build step.

set -euo pipefail

# We don't want to get stuck in some kind of interactive pager
export GIT_PAGER=cat

# Get the build date from the latest commit since it can be used across all
# builds
function build_date() {
  # It's tricky to do an RFC3339 format in a cross platform way, so we hardcode UTC
  : "${DATE_FORMAT:="%Y-%m-%dT%H:%M:%SZ"}"
  git show --no-show-signature -s --format=%cd --date=format:"$DATE_FORMAT" HEAD
}

# Get the revision, which is the latest commit SHA
function build_revision() {
  git rev-parse HEAD
}

# Determine our repository by looking at our origin URL
function repo() {
  basename -s .git "$(git config --get remote.origin.url)"
}

# Determine the root directory of the repository
function repo_root() {
  git rev-parse --show-toplevel
}

# Build terraform-mcp-server
function build() {
  local revision
  local build_date
  local ldflags
  local msg

  # Get or set our basic build metadata
  revision=$(build_revision)
  build_date=$(build_date) #
  : "${BIN_PATH:="dist/"}" #if not run by actions-go-build (enos local) then set this explicitly
  : "${GO_TAGS:=""}"
  : "${KEEP_SYMBOLS:=""}"

  # Build our ldflags
  msg="--> Building terraform-mcp-server revision $revision, built $build_date"

  # Strip the symbol and dwarf information by default
  if [ -n "$KEEP_SYMBOLS" ]; then
    ldflags=""
  else
    ldflags="-s -w "
  fi

  # if building locally with enos - don't need to set version/prerelease/metadata as the default from version_base.go will be used
  ldflags="${ldflags} -X terraform-mcp-server/version.GitCommit=$revision -X terraform-mcp-server/version.BuildDate=$build_date"

  if [[ ${BASE_VERSION+x} ]]; then
    msg="${msg}, base version ${BASE_VERSION}"
    ldflags="${ldflags} -X terraform-mcp-server/version.Version=$BASE_VERSION"
  fi

  if [[ ${PRERELEASE_VERSION+x} ]]; then
    msg="${msg}, prerelease ${PRERELEASE_VERSION}"
    ldflags="${ldflags} -X terraform-mcp-server/version.VersionPrerelease=$PRERELEASE_VERSION"
  fi

  if [[ ${METADATA_VERSION+x} ]]; then
    msg="${msg}, metadata ${METADATA_VERSION}"
    ldflags="${ldflags} -X terraform-mcp-server/version.VersionMetadata=$METADATA_VERSION"
  fi

  # Build terraform-mcp-server
  # Always use CGO_ENABLED=0 to ensure a statically linked binary is built
  echo "$msg"
  CGO_ENABLED=0 go build -o "$BIN_PATH" -tags "$GO_TAGS" -ldflags "$ldflags" -trimpath -buildvcs=false ./cmd/terraform-mcp-server
}

# Run the CRT Builder
function main() {
  # Assign the first argument or an empty string if it's not provided
  local sub_command="${1:-}"

  case "$sub_command" in
  build)
    build
  ;;

  date)
    build_date
  ;;

  revision)
    build_revision
  ;;
  *)
    # Provide a more informative error message when no subcommand is given
    if [ -z "$sub_command" ]; then
      echo "Error: No sub-command provided. Usage: $0 [build|date|revision]" >&2
    else
      echo "Error: Unknown sub-command '$sub_command'. Usage: $0 [build|date|revision]" >&2
    fi
    exit 1
  ;;
  esac
}

main "$@"

