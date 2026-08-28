#!/usr/bin/env bash
# .claude/hooks/production-gate.sh — PreToolUse hook on the Bash tool.
#
# Blocks a production deploy unless a human has authorised the release.
#
# Register it, matched to Bash and nothing else:
#
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command",
#                   "command": ".claude/hooks/production-gate.sh" }]
#     }]
#   }
#
# Exit codes are the contract, not a detail:
#   2  BLOCKED. Claude Code's blocking status for PreToolUse — the command
#      does not run, and the message on stderr goes back to the agent.
#   0  allowed.
# There is no third outcome. Every failure path below exits 2, including the
# ones that are this script's own fault: a missing jq, a payload shape it did
# not expect, an empty command, a bug. Claude Code treats any other non-zero
# status as a non-blocking error and runs the command anyway, so a gate that
# crashes with status 1 or 127 is a gate that approves the deploy. The EXIT
# trap rewrites anything that is not 0 or 2 into 2.
#
# ---------------------------------------------------------------------------
# THIS IS A TEMPLATE. AN UNEDITED COPY PROTECTS NOTHING.
#
# The deny list below describes an imaginary repo's deploy commands. It does
# not know yours. Before this file is worth committing:
#   1. Run the commands that actually ship your software past it and watch
#      them exit 2.
#   2. Run your ordinary build, test and read-only commands past it and watch
#      them exit 0.
#   3. Delete the entries that do not apply, and add the ones that do.
# A pattern nobody ever triggers is a pattern nobody notices is wrong. A gate
# never seen blocking a real deploy is decoration.
#
# Where a pattern is ambiguous it is written to over-block, because a false
# block costs a conversation and a false pass costs an outage. As shipped,
# `make deploy-staging`, `./deploy.sh preprod` and `helm upgrade --dry-run`
# are all blocked. That is the intended direction of the error, not a bug —
# but if your team meets it daily they will route around the gate, so tighten
# those entries to your real environment names.
# ---------------------------------------------------------------------------
#
# WHAT THIS GATE CANNOT SEE.
#
# It is a PreToolUse hook on the Bash tool, so a Bash command is the only
# thing it is ever handed. It does not see, and cannot block:
#   - a deploy through an MCP server — a cloud provider's deploy tool, a
#     platform's release tool. That is a different tool call entirely.
#   - a deploy caused by a file write — committing to a watched branch,
#     writing a GitOps manifest, editing a workflow file.
#   - anything CI does after the push. That runs on another machine where
#     this hook does not exist.
#   - a human typing the deploy in their own terminal.
#   - what a $expansion, a backtick or a $(...) will turn into, because that
#     is decided by the shell at run time and not by the text handed here.
#     The gate does not guess: a segment whose command word is one of the
#     sensitive binaries and whose words still carry an unresolved expansion
#     is BLOCKED, not allowed. So this is refused rather than missed — but it
#     is refused, not understood.
#   - what a script contains. `./run.sh` is judged as `run.sh`; the deploy on
#     line 40 of that file is invisible. Same for a command assembled from a
#     file's contents, a heredoc fed to a shell, or anything read off stdin.
#   - a binary renamed to something the deny list does not name. The list
#     matches command words, so a copy of terraform called `tf` walks past.
# Quoting, absolute and relative paths, `sh -c`, subshells and interposers
# like sudo/env/time/nohup ARE seen — see the normaliser below, which reduces
# `sh -c "/usr/bin/terraform \"apply\""` to `terraform apply` before any
# pattern is tried.
#
# Those unseeable routes need their own controls: permission deny rules for
# the deploy MCP tools, branch protection and required review for the writes,
# a protected environment with required reviewers in the CI provider. This
# hook is one layer. A repo holding only this one is unprotected.
#
# RELEASE_APPROVAL — WHAT IT ACTUALLY MEANS.
#
# A matched command is let through only when RELEASE_APPROVAL is set and
# non-blank in the environment of the Claude Code process itself. A human
# exports it before starting the session:
#
#     RELEASE_APPROVAL="CHG-4412 approved by j.okafor" claude
#
# The agent cannot set it from a Bash tool call. Hooks inherit Claude Code's
# environment, not the environment of the command being judged, so neither
# `export RELEASE_APPROVAL=1` in a tool call nor `RELEASE_APPROVAL=1 make
# release-prod` reaches this script.
#
# The agent CAN set it if it can write anything that feeds that environment:
# `env` in .claude/settings.json, a shell profile, a .env the launcher
# sources, or this file. Unprotected, the variable is a speed bump and not an
# authorisation. Deny those writes and pin them where neither the agent nor
# the engineer can edit them — managed-settings.json:
#
#     "permissions": { "deny": ["Edit(.claude/hooks/**)",
#                               "Edit(.claude/settings.json)",
#                               "Edit(~/.zshrc)", "Edit(.env*)"] }
#
# If you need an authorisation the agent has no route to at all, do not use an
# environment variable. Replace the body of require_approval() with one of:
#   - an out-of-band lookup — query the change-management API for an open,
#     human-approved release ticket naming this commit;
#   - a signature the agent cannot mint — verify a detached signature over the
#     commit SHA against a public key it cannot read;
#   - no local deploy path at all, which is the strongest and the simplest.
#     Deploys happen only in CI behind a protected environment with required
#     reviewers, and this gate refuses every local deploy unconditionally.

set -euo pipefail

# --- failing closed -------------------------------------------------------

block() {
  printf 'BLOCKED by production-gate: %s\n' "$1" >&2
  exit 2
}

# Anything that is not a deliberate 0 or 2 becomes a 2. Covers set -e aborts,
# missing interpreters, and any bug introduced when this template is edited.
on_exit() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    printf 'BLOCKED by production-gate: exited %s before reaching a verdict. Failing closed.\n' "$status" >&2
    exit 2
  fi
}
trap on_exit EXIT

require_approval() {
  # See RELEASE_APPROVAL above before trusting this check.
  if [ -z "$(printf '%s' "${RELEASE_APPROVAL:-}" | tr -d '[:space:]')" ]; then
    block "$1
This command deploys to production. It needs a named human's release
authorisation, which the agent cannot grant itself. A human restarts the
session with RELEASE_APPROVAL set, or the deploy goes through CI."
  fi
  printf 'production-gate: allowed (%s) under RELEASE_APPROVAL=%s\n' "$1" "$RELEASE_APPROVAL"
  exit 0
}

# --- normalising the command ----------------------------------------------
#
# The deny patterns are matched against a NORMALISED form of the command,
# never against the raw text. Raw-text matching is defeated by ordinary shell
# spellings - `npm "publish"`, `/usr/bin/npm publish`, `sh -c "npm publish"` -
# which are not attacks, just how commands get written. An agent emits the
# quoted form by accident. A gate that passes its own acceptance test and then
# fails on a pair of quotation marks is worse than no gate, because it is
# trusted.
#
# What the normaliser does, in order:
#   * splits the command on ; && || | & ( ) and newlines and judges EVERY
#     segment on its own, so `echo hi; ./deploy.sh prod` is judged twice;
#   * removes quoting and backslash escapes: `npm "publish"` -> `npm publish`;
#   * reduces argv[0] to its basename: /usr/bin/npm -> npm, ./deploy.sh -> deploy.sh;
#   * drops leading VAR=value assignments and interposer commands (sudo, env,
#     time, nohup, command, exec, xargs, stdbuf, nice, ionice, doas, setsid)
#     together with their own options, then judges what follows. `npx` and
#     `timeout <duration>` are treated the same way;
#   * unwraps `eval`, which is `sh -c` spelled shorter, and re-normalises what
#     it would have re-parsed;
#   * unwraps sh -c / bash -c / zsh -c and re-runs the whole normalisation on
#     the inner string, to GATE_MAX_DEPTH levels, BLOCKING if that is reached
#     rather than allowing;
#   * skips git's global options (-C dir, -c k=v, --git-dir=..., --no-pager,
#     ...) so that `git -C . push origin v1.2.3` reaches the push subcommand;
#   * flags a segment whose command word is a sensitive binary AND whose words
#     still contain a $expansion or a backtick. Variable indirection
#     (`p=publish; npm $p`) cannot be resolved without running the shell, so
#     the gate refuses instead of guessing. Failing closed on ambiguity is the
#     correct behaviour for a gate.
#
# Outputs (globals):
#   GATE_LINES      newline-separated canonical command lines, one per segment
#   GATE_AMBIG      1 when a sensitive command word carried an unresolved word
#   GATE_AMBIG_CMD  the canonical line that caused it
#   GATE_DEEP       1 when wrapper nesting hit GATE_MAX_DEPTH

GATE_MAX_DEPTH=3
GATE_TS=$'\001'        # separates tokens inside a segment
GATE_SS=$'\002'        # separates segments
GATE_LINES=''
GATE_AMBIG=0
GATE_AMBIG_CMD=''
GATE_DEEP=0
T_OUT=''

GATE_INTERPOSERS=' sudo doas env time timeout nohup command exec xargs stdbuf nice ionice setsid npx '
GATE_SHELLS=' sh bash zsh dash ksh ash busybox '
GATE_SENSITIVE=' npm git gh terraform helm kubectl aws docker make twine cargo netlify vercel wrangler mail sendmail msmtp curl '
# Tools that do many things, only some of which publish or deploy. For these
# the subcommand decides whether an unresolved expansion is ambiguous.
GATE_MULTIPURPOSE=' git make docker curl npm cargo '

# tokenize <string> -> T_OUT
# Each segment is prefixed by GATE_SS; each token inside it by GATE_TS and a
# single flag character, 1 when that token contained an unresolved expansion.
gate_tokenize() {
  local s=$1
  local n=${#s} i=0 ch cur='' started=0 exp=0 seg='' out='' in_s=0 in_d=0
  while [ "$i" -lt "$n" ]; do
    ch=${s:i:1}
    i=$((i+1))
    if [ "$in_s" = 1 ]; then
      if [ "$ch" = "'" ]; then in_s=0; else cur=$cur$ch; fi
      started=1
      continue
    fi
    case "$ch" in
      '\')
        if [ "$i" -lt "$n" ]; then cur=$cur${s:i:1}; i=$((i+1)); fi
        started=1
        continue ;;
      '"')
        if [ "$in_d" = 1 ]; then in_d=0; else in_d=1; fi
        started=1
        continue ;;
      "'")
        if [ "$in_d" = 1 ]; then cur=$cur$ch; else in_s=1; fi
        started=1
        continue ;;
      '$'|'`')
        cur=$cur$ch; exp=1; started=1
        continue ;;
    esac
    if [ "$in_d" = 1 ]; then cur=$cur$ch; started=1; continue; fi
    case "$ch" in
      ' '|$'\t')
        if [ "$started" = 1 ]; then
          seg=$seg$GATE_TS$exp$cur; cur=''; started=0; exp=0
        fi ;;
      ';'|'&'|'|'|'('|')'|$'\n')
        if [ "$started" = 1 ]; then
          seg=$seg$GATE_TS$exp$cur; cur=''; started=0; exp=0
        fi
        if [ -n "$seg" ]; then out=$out$GATE_SS$seg; fi
        seg='' ;;
      *)
        cur=$cur$ch; started=1 ;;
    esac
  done
  if [ "$started" = 1 ]; then seg=$seg$GATE_TS$exp$cur; fi
  if [ -n "$seg" ]; then out=$out$GATE_SS$seg; fi
  T_OUT=$out
}

# Drop the first token of $L. Relies on bash's dynamic scoping: $L is the
# caller's local list.
gate_pop() {
  if [ "$L" = "${L#*"$GATE_TS"}" ]; then L=''; else L=${L#*"$GATE_TS"}; fi
}

# Does <interposer> <option> consume the following word as its value?
gate_optarg() {
  case "$1:$2" in
    sudo:-u|sudo:-g|sudo:-p|sudo:-C|sudo:-h|sudo:-r|sudo:-t|sudo:-T|sudo:-U) return 0 ;;
    doas:-u|doas:-C) return 0 ;;
    env:-u|env:-C|env:-S) return 0 ;;
    xargs:-I|xargs:-i|xargs:-L|xargs:-n|xargs:-P|xargs:-s|xargs:-E|xargs:-d|xargs:-a) return 0 ;;
    nice:-n) return 0 ;;
    npx:-p|npx:-c|npx:--package|npx:--call) return 0 ;;
    timeout:-k|timeout:-s|timeout:--kill-after|timeout:--signal) return 0 ;;
    ionice:-c|ionice:-n|ionice:-p|ionice:-t) return 0 ;;
    stdbuf:-i|stdbuf:-o|stdbuf:-e) return 0 ;;
  esac
  return 1
}

# Is $1 a bare duration, as `timeout 30 cmd` and `timeout 1.5h cmd` spell it?
gate_is_duration() {
  case "$1" in
    ''|*[!0-9smhd.]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Is $1 a shell variable assignment (FOO=bar), i.e. not part of argv?
gate_is_assign() {
  case "$1" in
    [A-Za-z_]*=*)
      case "${1%%=*}" in
        *[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
      esac ;;
  esac
  return 1
}

gate_segment() {
  local blob=$1 depth=$2
  local L head flag text base cw line hasexp=0 guard=0 have=0 inner opt first
  L=${blob#"$GATE_TS"}

  while [ -n "$L" ]; do
    guard=$((guard+1))
    if [ "$guard" -gt 64 ]; then GATE_DEEP=1; return 0; fi
    head=${L%%"$GATE_TS"*}
    flag=${head:0:1}
    text=${head:1}
    base=${text##*/}

    if [ -z "$text" ]; then gate_pop; continue; fi
    if gate_is_assign "$text"; then gate_pop; continue; fi

    # `eval` is `sh -c` by another name: it re-parses its arguments as a
    # command. Join what follows back into one string and run the whole
    # normalisation on it, exactly as the shell would.
    if [ "$base" = eval ]; then
      gate_pop
      inner=''
      first=1
      while [ -n "$L" ]; do
        head=${L%%"$GATE_TS"*}
        if [ "$first" = 1 ]; then inner=${head:1}; first=0; else inner="$inner ${head:1}"; fi
        gate_pop
      done
      if [ -n "$inner" ]; then gate_walk "$inner" "$((depth + 1))"; fi
      return 0
    fi

    case "$GATE_INTERPOSERS" in
      *" $base "*)
        gate_pop
        while [ -n "$L" ]; do
          head=${L%%"$GATE_TS"*}
          opt=${head:1}
          case "$opt" in
            -*)
              gate_pop
              if gate_optarg "$base" "$opt"; then gate_pop; fi ;;
            *)
              if gate_is_assign "$opt"; then
                gate_pop
              elif [ "$base" = timeout ] && gate_is_duration "$opt"; then
                gate_pop
              else
                break
              fi ;;
          esac
        done
        continue ;;
    esac

    case "$GATE_SHELLS" in
      *" $base "*)
        gate_pop
        while [ -n "$L" ]; do
          head=${L%%"$GATE_TS"*}
          opt=${head:1}
          case "$opt" in
            --*) gate_pop ;;
            -*)
              case "${opt#-}" in
                *[!A-Za-z]*) gate_pop ;;
                *c*)
                  gate_pop
                  if [ -n "$L" ]; then
                    head=${L%%"$GATE_TS"*}
                    inner=${head:1}
                    gate_walk "$inner" "$((depth + 1))"
                  fi
                  return 0 ;;
                *) gate_pop ;;
              esac ;;
            *) break ;;
          esac
        done
        continue ;;
    esac

    have=1
    break
  done

  if [ "$have" = 0 ]; then return 0; fi

  cw=$base
  if [ "$flag" = 1 ]; then hasexp=1; fi
  gate_pop

  if [ "$cw" = git ]; then
    while [ -n "$L" ]; do
      head=${L%%"$GATE_TS"*}
      opt=${head:1}
      case "$opt" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)
          gate_pop; gate_pop ;;
        --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--config-env=*)
          gate_pop ;;
        -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks)
          gate_pop ;;
        *) break ;;
      esac
    done
  fi

  line=$cw
  while [ -n "$L" ]; do
    head=${L%%"$GATE_TS"*}
    if [ "${head:0:1}" = 1 ]; then hasexp=1; fi
    text=${head:1}
    line="$line ${text//$'\n'/ }"
    gate_pop
  done

  # Unresolved $ or backtick on a sensitive command word means the gate cannot
  # see what will actually run, and a gate that cannot see fails closed.
  #
  # But the command WORD is too coarse for the multi-purpose tools. Blocking
  # every `git commit -m "$msg"` - a spelling agents emit constantly - is how a
  # gate gets switched off within a day, and a gate that is off protects
  # nothing. So for those, the SUBCOMMAND decides: `git push origin $TAG` is
  # ambiguous and blocks; `git commit -m "$msg"` is not and does not.
  local ambig=0
  case "$GATE_SENSITIVE" in
    *" $cw "*) ambig=1 ;;
  esac
  case "$GATE_MULTIPURPOSE" in
    *" $cw "*)
      ambig=0
      # If the SUBCOMMAND is itself the unresolved part - `npm $p`, `git $op` -
      # the gate cannot know which subcommand this is, so it fails closed. That
      # is different from `git commit -m "$msg"`, where the subcommand is known
      # and only an argument is opaque.
      local _sub
      # shellcheck disable=SC2086  # deliberate word-splitting of a normalised line
      set -- $line
      _sub=${2:-}
      case "$_sub" in
        *'$'*|*'`'*) ambig=1 ;;
      esac
      case " $line " in
        *" git push "*|*" git tag "*|*" npm publish "*|*" npm pack "*\
        |*" cargo publish "*|*" docker push "*|*" make release "*\
        |*" make deploy "*|*" make publish "*|*" curl "*"-X POST"*\
        |*" curl "*"--upload-file"*|*" curl "*"-T "*) ambig=1 ;;
      esac ;;
  esac
  if [ "$ambig" = 1 ] && [ "$hasexp" = 1 ]; then
    GATE_AMBIG=1; GATE_AMBIG_CMD=$line
  fi

  GATE_LINES=$GATE_LINES$line'
'
}

gate_walk() {
  local depth=$2 blob rest seg
  if [ "$depth" -gt "$GATE_MAX_DEPTH" ]; then GATE_DEEP=1; return 0; fi
  gate_tokenize "$1"
  blob=$T_OUT
  rest=$blob
  while [ -n "$rest" ]; do
    rest=${rest#"$GATE_SS"}
    seg=${rest%%"$GATE_SS"*}
    if [ "$seg" = "$rest" ]; then rest=''; else rest=${rest#*"$GATE_SS"}; fi
    if [ -n "$seg" ]; then gate_segment "$seg" "$depth"; fi
  done
}

gate_normalise() {
  GATE_LINES=''
  GATE_AMBIG=0
  GATE_AMBIG_CMD=''
  GATE_DEEP=0
  gate_walk "$1" 0
}

# --- the deny list --------------------------------------------------------
#
# EDIT THIS. It is the whole gate; everything else is plumbing.
#
# Each entry is a label and an extended regular expression, matched
# case-insensitively against each NORMALISED segment (see above). A pattern is
# anchored with ^, which now means "this segment's command word" and nothing
# else — the normaliser has already split the command line, stripped quoting,
# reduced argv[0] to its basename and removed sudo/env/time-style interposers.
# That anchoring is the point: it is why `echo make release-prod` is not a
# deploy, and why `git pull && /usr/bin/make release-prod` still is.

ARG="[^[:space:]]*"                        # one bare argument
MID="([[:space:]]+[^[:space:]]+)*"         # intervening flags and arguments

DENY_LABELS=()
DENY_PATTERNS=()
deny() { DENY_LABELS+=("$1"); DENY_PATTERNS+=("$2"); }

# A make target naming release, deploy or prod. `make test`, `make build` and
# `make lint` are deliberately not here.
deny "make release/deploy/prod target" \
     "^make${MID}[[:space:]]+${ARG}(release|deploy|prod|publish)"

# kubectl aimed at a production context or namespace. Coarse on purpose: this
# also blocks reads against prod. Narrow it to
# (apply|delete|rollout|scale|patch|create) if that is too much.
deny "kubectl against a production context or namespace" \
     "^kubectl.*(--context|--kube-context|--namespace|-n)[=[:space:]]+${ARG}(prod|live)"

# helm writing to a cluster. Add install and rollback if you use them.
deny "helm upgrade" \
     "^helm${MID}[[:space:]]+upgrade"

# terraform changing real infrastructure. plan is not here, on purpose.
deny "terraform apply/destroy" \
     "^terraform${MID}[[:space:]]+(apply|destroy)"

# A push to a production registry. REPLACE prod|release|live WITH YOUR OWN
# REGISTRY HOSTNAME — it is the one pattern here most likely to be both
# wrong and silently wrong.
deny "docker push to a production registry" \
     "^docker${MID}[[:space:]]+push[[:space:]]+${ARG}(prod|release|live)"

# A deploy script invoked with a prod-ish argument. Because the normaliser
# reduces argv[0] to a basename, this one entry now covers `./deploy.sh prod`,
# `bash scripts/deploy.sh prod` and `sh -c "/opt/ci/deploy.sh --env prod"`
# alike. Note the remaining limit: a bare `./deploy.sh` with no argument is
# NOT caught, so if your script defaults to production, drop the argument
# requirement.
deny "deploy* script with a production argument" \
     "^deploy${ARG}[[:space:]]+.*(prod|live|release)"

# --- reading the payload --------------------------------------------------

command -v jq >/dev/null 2>&1 ||
  block "jq is not on PATH, so this gate cannot read the command it is meant to judge."

payload="$(cat)"
[ -n "$(printf '%s' "$payload" | tr -d '[:space:]')" ] ||
  block "empty hook payload on stdin. Nothing to judge, so nothing is approved."

# Every branch here is a shape this script does not understand. It refuses
# rather than guesses. jq's own diagnostic is folded into $cmd so the message
# says which shape arrived.
cmd="$(printf '%s' "$payload" | jq -er '
  if type != "object" then
    error("payload is not a JSON object")
  elif ((.tool_name // "Bash") != "Bash") then
    error("fired on tool \(.tool_name) — register this hook on the Bash matcher only")
  elif ((.tool_input | type) != "object") then
    error("payload has no .tool_input object")
  elif ((.tool_input.command | type) != "string") then
    error(".tool_input.command is not a string")
  else .tool_input.command end' 2>&1)" ||
  block "cannot read the hook payload: ${cmd:-jq failed and said nothing}"

[ -n "$(printf '%s' "$cmd" | tr -d '[:space:]')" ] ||
  block "the payload carried an empty command. A gate that cannot see the command does not approve it."

[ "${#DENY_PATTERNS[@]}" -gt 0 ] ||
  block "the deny list is empty, so this gate decides nothing. Fill it in or remove the hook."

# --- the verdict ----------------------------------------------------------

gate_normalise "$cmd"

if [ "$GATE_DEEP" = 1 ]; then
  block "shell wrappers in

  $cmd

are nested deeper than this gate unwraps (${GATE_MAX_DEPTH}), so it cannot see what is
finally run. It refuses rather than guesses. Run the inner command directly."
fi

if [ "$GATE_AMBIG" = 1 ]; then
  block "this command could not be statically resolved:

  $GATE_AMBIG_CMD

A \$expansion or a backtick decides what that binary is asked to do, and what
it expands to is only known once the shell runs it. The gate cannot read it,
so it does not approve it — failing closed on ambiguity is the point of a
gate, not a limitation of this one. Write the command out literally and it
will be judged on what it says."
fi

shopt -s nocasematch
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  for ((i = 0; i < ${#DENY_PATTERNS[@]}; i++)); do
    if [[ $seg =~ ${DENY_PATTERNS[$i]} ]]; then
      require_approval "${DENY_LABELS[$i]} — in \`$seg\`"
    fi
  done
done <<< "$GATE_LINES"

exit 0
