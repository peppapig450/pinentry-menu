#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf "Error: %s\n" "$*" >&2
  exit 1
}

dief() {
  local fmt="$1"
  shift
  printf "Error: ${fmt}\n" "$@" >&2
  exit 1
}

populate_runners_map() {
  local -n runners_ref="$1"
  local delim="$2"

  # Define raw runner commands with space-separated values
  # Placeholders MUST be in the order $desc and then $prompt
  # This ensures that our printf substitution works correctly
  local -A raw_runners=(
    ["rofi"]="rofi -dmenu -input /dev/null -password -lines 0"
    ["wofi"]="wofi --dmenu --password -p %s"
    ["fuzzel"]='fuzzel --prompt-only %s --placeholder=%s: --cache /dev/null --dmenu --password'
  )

  local runner
  for runner in "${!raw_runners[@]}"; do
    # Replace spaces with ASCII Unit Seperator
    runners_ref["${runner}"]="${raw_runners[${runner}]// /${delim}}"
  done
}

check_command() {
  local cmd="$1"

  if command -v "$cmd" &> /dev/null; then
    printf "%s" "$cmd"
    return
  fi

  return 1
}

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

check_environment() {
  if ! printenv DISPLAY &> /dev/null && ! printenv WAYLAND_DISPLAY &> /dev/null; then
    die "DISPLAY or WAYLAND_DISPLAY must be set."
  fi
}

run_prompt() {
  local delim="$1"
  local cmd="$2"
  local prompt="$3"
  local message="$4"

  # Substitute the placeholders with our prompt and message values
  local full_cmd
  full_cmd="$(printf "$cmd" "$desc" "$prompt")"

  # Build array for safe execution of command, using our custom delim
  IFS="$delim" read -ra cmd_parts <<< "$full_cmd"
  env "${cmd_parts[@]}"
}

send_ok() {
  printf "OK\n"
}

send_data() {
  local data="$1"
  printf "D %s\n" "$data"
}

send_error() {
  local code="$1"
  local msg="$2"
  printf "ERR %s %s\n" "$code" "$msg"
}

pinentry_loop() {
  local runner="$1"
  local run_cmd="$2"
  local delim="$3"
  local desc error prompt

  while read -r cmd rest; do
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
        desc="$rest"
        send_ok
        ;;
      SETERROR)
        error="_ERO_${rest@U}_ERC"
        send_ok
        ;;
      SETPROMPT)
        prompt="${rest//:/}"
        send_ok
        ;;
      GETPIN)
        local message password
        message="$(format_message "${error}${desc}")"
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

main() {
  local runner="${1:-}"
  local -A runners

  # use the ASCII Unit Seperator for safe passing of messages containing spacse
  # to the runners, this allows us to build the command into an array safely.
  local delim=$'\x1F'

  check_environment
  populate_runners_map runners "$delim"

  local resolved_runner
  resolved_runner="$(get_runner_command "$runner" runners)" || die "No usable runner"

  local run_cmd="${runners[${resolved_runner}]}"
  pinentry_loop "$resolved_runner" "$run_cmd" "$delim"
}

if ! (return 0 2> /dev/null); then
  main "$@"
fi
