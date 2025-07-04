#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# pinentry-runner - A pluggable prompt interface compatible with GnuPG's pinentry
#
# This script implements a pinentry interface using various graphical menu tools
# like `rofi`, `wofi`, and `fuzzel`. It is intended to be used as a drop-in
# replacement for `pinentry` by parsing pinentry protocol commands over stdin.
#
# Features:
# - Dynamically selects a supported runner available on the system.
# - Provides graphical password prompt functionality with custom descriptions.
# - Follows pinentry protocol and responds accordingly to commands such as
#   SETDESC, SETPROMPT, GETPIN, GETINFO, and BYE.
#
# Dependencies:
# - At least one supported runner (rofi, wofi, or fuzzel) must be installed.
# - DISPLAY or WAYLAND_DISPLAY must be set for graphical prompts to work.
#
# Usage:
#   Can be invoked directly or through GnuPG by setting:
#   export PINENTRY_USER_DATA=your_runner_choice  # Optional
#   export PINENTRY_PROGRAM=/path/to/this/script
#
# -----------------------------------------------------------------------------
set -Eeuo pipefail

# die: Print an error message and exit
# Arguments:
#   $* - Error message to print
die() {
  printf "Error: %s\n" "$*" >&2
  exit 1
}

# dief: Print a formatted error message and exit
# Arguments:
#   $1 - printf-style format string
#   $@ - values to substitute into the format
dief() {
  local fmt="$1"
  shift
  printf "Error: ${fmt}\n" "$@" >&2
  exit 1
}

# populate_runners_map: Populate an associative array with command templates for runners
# Arguments:
#   $1 - Name of the associative array to populate (passed by reference)
#   $2 - Delimiter used to split the command for safe execution
# Side Effects:
#   Populates the array with commands using custom delimiter
populate_runners_map() {
  local -n runners_ref="$1"
  local delim="$2"

  # Define raw runner commands with space-separated values to take $prompt
  # This ensures that our printf substitution works correctly
  local -A raw_runners=(
    ["rofi"]="rofi -dmenu -input /dev/null -password -lines 0 -p %s -mesg %s"
    ["wofi"]="wofi --dmenu --cache-file /dev/null --password --prompt %s"
    ["fuzzel"]="fuzzel --prompt-only=%s --cache /dev/null --dmenu --password"
  )

  local runner
  for runner in "${!raw_runners[@]}"; do
    # Replace spaces with ASCII Unit Seperator
    runners_ref["${runner}"]="${raw_runners[${runner}]// /${delim}}"
  done
}

# check_command: Check if a given command exists on the system
# Arguments:
#   $1 - Command name to check
# Outputs:
#   Prints the command name if found
# Returns:
#   0 if the command exists, non-zero otherwise
check_command() {
  local cmd="$1"

  if command -v "$cmd" &> /dev/null; then
    printf "%s" "$cmd"
    return
  fi

  return 1
}

# get_runner_command: Resolve a runner command from the available or requested runners
# Arguments:
#   $1 - Requested runner name (optional)
#   $2 - Name of associative array containing available runners (passed by reference)
# Outputs:
#   Prints the resolved runner name
# Returns:
#   0 if a runner was found, exits with error otherwise
get_runner_command() {
  local requested_runner="${1:-}"
  local -n _runners="$2"

  if [[ -n ${requested_runner} ]]; then
    if ! [[ -v _runners[${requested_runner}] ]]; then
      dief "requested runner '%s' not supported, exiting." "${requested_runner}"
    fi

    if runner="$(check_command "${requested_runner}")"; then
      printf "%s" "$runner"
      return
    else
      printf "Warning: requested runner '%s' not found, falling back." "${runner}" >&2
    fi
  fi

  # Search supported runners for ones found on system, use the first one.
  # NOTE: I'm not sure if order is preserved as it is declared so this could
  # possibly return a different runner each time if multiple are installed.
  for possible_runner in "${!_runners[@]}"; do
    if runner="$(check_command "${possible_runner}")"; then
      printf "%s" "$runner"
      return
    fi
  done

  die "no supported runners found"
}

# check_environment: Ensure DISPLAY or WAYLAND_DISPLAY is set
# Exits with error if neither is found
check_environment() {
  if ! printenv DISPLAY &> /dev/null && ! printenv WAYLAND_DISPLAY &> /dev/null; then
    die "DISPLAY or WAYLAND_DISPLAY must be set."
  fi
}

# run_prompt: Run the prompt command with substituted values
# Arguments:
#   $1 - Delimiter used for command splitting
#   $2 - Command template (with printf placeholders)
#   $3 - Prompt text
#   $4 - Message text
# Outputs:
#   Runs the chosen runner command via env and returns its stdout
run_prompt() {
  local delim="$1"
  local cmd="$2"
  local prompt="$3"
  local message="$4"

  # TODO: not sure what to do with message for right now, as using it as a placeholder in
  # in fuzzel does not look good, its shoved together with the prompt

  # Substitute the placeholders with our prompt and message values
  local full_cmd
  # Don't use prompt for right now since I am not sure how to properly handle it,
  # see TODO above
  full_cmd="$(printf "$cmd" "${message}")"

  # Build array for safe execution of command, using our custom delim
  IFS="$delim" read -ra cmd_parts <<< "$full_cmd"
  env "${cmd_parts[@]}"
}

# parse_setdesc: Parse and decode the SETDESC value into prompt and message components
# Arguments:
#   $1 - Raw SETDESC input string (URL-encoded, newline-delimited)
#   $2 - Name of variable to store the parsed prompt (passed by reference)
#   $3 - Name of variable to store the parsed message (passed by reference)
# Outputs:
#   Sets the referenced variables with decoded prompt and message
# Side Effects:
#   Defines and unsets a temporary _urldecode helper function
parse_setdesc() {
  local setdesc_input="$1"
  local -n _prompt="$2"
  local -n _message="$3"

  _urldecode() {
    # Decode URL-encoded string: '+' becomes space, %XX becomes corresponding character
    # This is necessary because SETDESC values are URL-encoded
    local data="${1//+/ }"
    printf "%b" "${data//%/\\x}"
  }

  # Cleanup our little helper function
  trap 'unset -f _urldecode' RETURN

  local decoded
  decoded="$(_urldecode "$setdesc_input")" # Decode the input into a readable string

  local -a targets
  # Read up to two lines from the decoded string into an array.
  # The first line is the prompt; the second is the message.
  mapfile -t -n2 targets < <(printf "%s\n" "$decoded")

  # If the message line is surrounded by quotes (common in GPG), strip them
  targets[1]="${targets[1]%\"}"
  targets[1]="${targets[1]#\"}"

  # Add a colon suffix to the prompt to make our runners happy
  # TODO: some runners append the colon themselves, we neeed to handle that eventually
  _prompt="${targets[0]}:"
  # Remove any trailing colon so our placeholder doesn't look like a prompt
  _message="${targets[1]%:}"
}

# send_ok: Send an OK response to stdout
send_ok() {
  printf "OK\n"
}

# send_data: Send a data line (D ...) to stdout
# Arguments:
#   $1 - Data string to send
send_data() {
  local data="$1"
  printf "D %s\n" "$data"
}

# send_error: Send an error response to stdout
# Arguments:
#   $1 - Error code
#   $2 - Error message
send_error() {
  local code="$1"
  local msg="$2"
  printf "ERR %s %s\n" "$code" "$msg"
}

# pinentry_loop: Main loop that reads and responds to pinentry protocol commands
# Arguments:
#   $1 - Name of the selected runner
#   $2 - Command template associated with the runner
#   $3 - Delimiter used for splitting commands
# Inputs:
#   Reads pinentry commands from stdin
# Side Effects:
#   Sends responses to stdout
pinentry_loop() {
  local runner="$1"
  local run_cmd="$2"
  local delim="$3"
  local error prompt message

  if [[ -n "${PINENTRY_DEBUG:-}" ]]; then
    : > /tmp/testing-pinentry
    exec {fd}>> /tmp/testing-pinentry
    log_debug() {
      printf '%(%Y-%m-%dT%H:%M:%S%z)T [RECV] %s %s\n' -1 "$1" "$2" >&"$fd"
    }
  else
    log_debug() { :; }
  fi

  printf "OK Pleased to meet you\n"

  while read -r cmd rest; do
    log_debug "$cmd" "$rest"
    case "$cmd" in
      \#*) send_ok ;;
      GETINFO)
        case "$rest" in
          flavor)
            send_data "$runner"
            send_ok
            ;;
          version)
            send_data "0.1"
            send_ok
            ;;
          ttyinfo)
            send_data "- - -"
            send_ok
            ;;
          pid)
            send_data "$$"
            send_ok
            ;;
        esac
        ;;
      SETDESC)
        parse_setdesc "$rest" prompt message
        send_ok
        ;;
      SETERROR)
        error="_ERO_${rest@U}_ERC"
        send_ok
        ;;
      SETPROMPT)
        prompt="${prompt//:/}"
        send_ok
        ;;
      GETPIN)
        local password
        message="${error:-}${message}"

        if password="$(run_prompt "$delim" "$run_cmd" "$prompt" "$message")"; then
          [[ -n ${password:-} ]] && send_data "$password"
        fi
        send_ok
        ;;
      BYE)
        printf "OK closing connection\n"
        exit 0
        ;;
      *) send_ok ;;
    esac
  done
}

# main: Entry point for the script
# Arguments:
#   $1 - Optional runner name to use
# Behavior:
#   - Validates environment
#   - Selects a runner
#   - Starts the pinentry processing loop
main() {
  local runner="${1:-}"
  local -A runners

  # Use the ASCII Unit Separator (US, \x1F) as a delimiter for splitting commands.
  # This avoids issues with spaces in prompt strings or arguments,
  # since this character is highly unlikely to appear in real input.
  local delim=$'\x1F'

  check_environment
  populate_runners_map runners "$delim"

  local resolved_runner
  resolved_runner="$(get_runner_command "$runner" runners)" || die "No usable runner"

  local run_cmd="${runners[${resolved_runner}]}"
  pinentry_loop "$resolved_runner" "$run_cmd" "$delim"
}

# Avoid running if sourced
if ! (return 0 2> /dev/null); then
  main "$(printenv PINENTRY_USER_DATA)"
fi
