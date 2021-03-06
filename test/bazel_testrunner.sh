#!/bin/bash

# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Test runner that sets up the environment for Apple shell integration tests.
#
# Use the `apple_shell_test` rule in //test:test_rules.bzl to spawn this.
#
# Usage:
#   bazel_testrunner.sh <test_script>
#
# test_script: The name of the test script to execute inside the test
#     directory.

test_script="$1"; shift

# Update this to change the default version of Xcode used in tests. (Later in
# this script we search for it and will fallback to a different version if
# found, but this lets us fix a default version for CI if desired.)
export XCODE_VERSION_FOR_TESTS=8.3.3

function print_message_and_exit() {
  echo "$1" >&2; exit 1;
}

CURRENT_SCRIPT="${BASH_SOURCE[0]}"
# Go to the directory where the script is running
cd "$(dirname ${CURRENT_SCRIPT})" \
  || print_message_and_exit "Unable to access "$(dirname ${CURRENT_SCRIPT})""

DIR=$(pwd)
# Load the unit test framework
source "$DIR/unittest.bash" || print_message_and_exit "unittest.bash not found!"

# Load the test environment
function create_new_workspace() {
  new_workspace_dir="${1:-$(mktemp -d ${TEST_TMPDIR}/workspace.XXXXXXXX)}"
  rm -fr "${new_workspace_dir}"
  mkdir -p "${new_workspace_dir}"
  cd "${new_workspace_dir}"

  touch WORKSPACE
  cat > WORKSPACE <<EOF
workspace(name = 'build_bazel_rules_apple_integration_tests')

git_repository(
    name = "bazel_skylib",
    remote = "https://github.com/bazelbuild/bazel-skylib.git",
    tag = "0.2.0",
)

local_repository(
    name = 'build_bazel_rules_apple',
    path = '$(rlocation build_bazel_rules_apple)',
)
EOF
}

# Set-up a clean default workspace.
function setup_clean_workspace() {
  export WORKSPACE_DIR="${TEST_TMPDIR}/workspace"
  echo "setting up client in ${WORKSPACE_DIR}" > "$TEST_log"
  rm -fr "${WORKSPACE_DIR}"
  create_new_workspace "${WORKSPACE_DIR}"
  [ "${new_workspace_dir}" = "${WORKSPACE_DIR}" ] || \
    { echo "Failed to create workspace" >&2; exit 1; }
  export BAZEL_INSTALL_BASE=$(bazel info install_base)
  export BAZEL_GENFILES=$(bazel info bazel-genfiles "${EXTRA_BUILD_OPTIONS[@]:-}")
  export BAZEL_BIN=$(bazel info bazel-bin "${EXTRA_BUILD_OPTIONS[@]:-}")
}

# Any remaining arguments are passed to every `bazel build` invocation in the
# subsequent tests (see `do_build` in apple_shell_testutils.sh).
export EXTRA_BUILD_OPTIONS=( "$@" ); shift $#
echo "Applying extra options to each build: ${EXTRA_BUILD_OPTIONS[*]:-}" > "$TEST_log"

# Try to find the desired version of Xcode installed on the system. If it's not
# present, fallback to the most recent version currently installed and warn the
# user that results might be affected by this. (This makes it easier to support
# local test runs without having to change the version above from the CI
# default.)
readonly XCODE_QUERY=$(bazel query \
    "attr(aliases, $XCODE_VERSION_FOR_TESTS, " \
    "labels(versions, @local_config_xcode//:host_xcodes))" | \
    head -n 1)
if [[ -z "$XCODE_QUERY" ]]; then
  readonly OLD_XCODE_VERSION="$XCODE_VERSION_FOR_TESTS"
  XCODE_VERSION_FOR_TESTS=$(bazel query \
      "labels(versions, @local_config_xcode//:host_xcodes)" | \
      head -n 1 | \
      sed s#@local_config_xcode//:version## | \
      sed s#_#.#g)

  printf "WARN: The desired version of Xcode ($OLD_XCODE_VERSION) was not " > "$TEST_log"
  printf "installed; using the highest version currently installed instead " > "$TEST_log"
  printf "($XCODE_VERSION_FOR_TESTS). Note that this may produce unpredictable " > "$TEST_log"
  printf "results in tests that depend on the behavior of a specific version " > "$TEST_log"
  printf "of Xcode.\n" > "$TEST_log"
fi

setup_clean_workspace

source "$(rlocation build_bazel_rules_apple/test/apple_shell_testutils.sh)"
source "$(rlocation build_bazel_rules_apple/test/${test_script})"
