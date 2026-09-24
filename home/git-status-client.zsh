# Source from the interactive shell with the zsh executable and worker path.
# A single coprocess handles every prompt request in this shell.
if (( ${_I4_GIT_STATUS_STARTED:-0} )); then
  print -ru2 -- 'git status daemon already launched in this shell; refusing a second launch'
  return 1
fi
zmodload zsh/parameter
autoload -Uz add-zsh-hook

typeset -gi _I4_GIT_STATUS_SEQ=0 _I4_GIT_STATUS_INFLIGHT=0
typeset -gi _I4_GIT_STATUS_READY=0 _I4_GIT_STATUS_FAILED=0 _I4_GIT_STATUS_STARTED=0
typeset -g _I4_GIT_STATUS_OUTPUT=
typeset -g _I4_GIT_STATUS_ZSH=$1 _I4_GIT_STATUS_DAEMON=$2

function _i4_git_status_start() {
  if (( _I4_GIT_STATUS_STARTED )); then
    print -ru2 -- 'git status daemon already launched in this shell; refusing a second launch'
    return 1
  fi
  _I4_GIT_STATUS_STARTED=1
  () {
    setopt local_options no_monitor
    coproc "$_I4_GIT_STATUS_ZSH" -f "$_I4_GIT_STATUS_DAEMON"
  }
  typeset -gi _I4_GIT_STATUS_PID=$!
  disown
  exec {_I4_GIT_STATUS_REQUEST_FD}>&p
  exec {_I4_GIT_STATUS_RESPONSE_FD}<&p
  zle -F $_I4_GIT_STATUS_RESPONSE_FD _i4_git_status_response
}

function _i4_git_status_redraw() {
  if (( $+functions[_p9k_set_prompt] )); then
    eval "$__p9k_intro"
    _p9k__refresh_reason=gitstatus
    _p9k_set_prompt
    _p9k__refresh_reason=
    _p9k_reset_prompt
  else
    zle reset-prompt
  fi
}

function _i4_git_status_send() {
  local name payload
  local -a git_names
  for name in ${(k)parameters[(I)GIT_*]}; do
    [[ ${parameters[$name]} == *export* ]] && git_names+=("$name")
  done

  # Quote each field so paths and exported Git variables may contain newlines.
  # Line reads do not make Zsh change the daemon's inherited terminal settings.
  payload="${(q)_I4_GIT_STATUS_SEQ}"$'\n'"${(q)PWD}"$'\n'"${(q)PATH}"$'\n'"${(q)${#git_names}}"$'\n'
  for name in "${git_names[@]}"; do
    payload+="${(q)name}"$'\n'"${(q)${(P)name}}"$'\n'
  done

  if print -rnu $_I4_GIT_STATUS_REQUEST_FD -- "$payload" 2>/dev/null; then
    _I4_GIT_STATUS_INFLIGHT=1
  else
    _i4_git_status_fail 'request pipe closed'
  fi
}

function _i4_git_status_precmd() {
  (( ++_I4_GIT_STATUS_SEQ ))
  if [[ $PWD != $_I4_GIT_STATUS_DIR ]]; then
    _I4_GIT_STATUS_READY=0
    _I4_GIT_STATUS_OUTPUT=
    typeset -g _I4_GIT_STATUS_DIR=$PWD
  fi
  (( _I4_GIT_STATUS_INFLIGHT )) || _i4_git_status_send
}

function _i4_git_status_response() {
  local fd=$1 response git_result
  if [[ -n $2 ]] || ! IFS= read -r -u $fd response; then
    _i4_git_status_fail 'response pipe closed'
    _i4_git_status_redraw
    return
  fi

  _I4_GIT_STATUS_INFLIGHT=0
  if [[ ${response%%:*} != $_I4_GIT_STATUS_SEQ ]]; then
    _i4_git_status_send
    (( _I4_GIT_STATUS_FAILED )) && _i4_git_status_redraw
    return
  fi
  git_result=${response#*:}
  if [[ $git_result != $_I4_GIT_STATUS_OUTPUT ]]; then
    _I4_GIT_STATUS_OUTPUT=$git_result
    _I4_GIT_STATUS_READY=0
    if [[ -n $git_result ]]; then
      local -a fields=("${(@ps:\x1f:)git_result}")
      if (( $#fields == 12 )); then
        typeset -g VCS_STATUS_RESULT=ok-async
        typeset -g VCS_STATUS_WORKDIR=$PWD
        typeset -g VCS_STATUS_REMOTE_URL=
        typeset -g VCS_STATUS_LOCAL_BRANCH=$fields[1]
        typeset -g VCS_STATUS_REMOTE_BRANCH=$fields[2]
        typeset -g VCS_STATUS_ACTION=$fields[3]
        typeset -gi VCS_STATUS_NUM_STAGED=$fields[4]
        typeset -gi VCS_STATUS_NUM_UNSTAGED=$fields[5]
        typeset -gi VCS_STATUS_NUM_UNTRACKED=$fields[6]
        typeset -gi VCS_STATUS_NUM_CONFLICTED=$fields[7]
        typeset -gi VCS_STATUS_COMMITS_AHEAD=$fields[8]
        typeset -gi VCS_STATUS_COMMITS_BEHIND=$fields[9]
        typeset -gi VCS_STATUS_STASHES=$fields[10]
        typeset -g VCS_STATUS_TAG=$fields[11]
        typeset -g VCS_STATUS_COMMIT=$fields[12]
        typeset -gi VCS_STATUS_HAS_STAGED='VCS_STATUS_NUM_STAGED > 0'
        typeset -gi VCS_STATUS_HAS_UNSTAGED='VCS_STATUS_NUM_UNSTAGED > 0'
        typeset -gi VCS_STATUS_HAS_UNTRACKED='VCS_STATUS_NUM_UNTRACKED > 0'
        typeset -gi VCS_STATUS_HAS_CONFLICTED='VCS_STATUS_NUM_CONFLICTED > 0'
        typeset -gi VCS_STATUS_NUM_UNSTAGED_DELETED=0
        _I4_GIT_STATUS_READY=1
      fi
    fi
    _i4_git_status_redraw
  fi
}

function _i4_git_status_fail() {
  (( _I4_GIT_STATUS_FAILED )) && return
  _I4_GIT_STATUS_FAILED=1
  _I4_GIT_STATUS_INFLIGHT=0
  _I4_GIT_STATUS_READY=0
  _I4_GIT_STATUS_OUTPUT=
  local pid=$_I4_GIT_STATUS_PID
  _i4_git_status_stop
  add-zsh-hook -d precmd _i4_git_status_precmd
  print -ru2 -- "git status daemon (PID $pid) failed: $1; Git prompt disabled for this shell"
}

function _i4_git_status_stop() {
  (( _I4_GIT_STATUS_PID > 0 )) || return
  local pid=$_I4_GIT_STATUS_PID
  _I4_GIT_STATUS_PID=0
  zle -F $_I4_GIT_STATUS_RESPONSE_FD 2>/dev/null
  exec {_I4_GIT_STATUS_REQUEST_FD}>&-
  exec {_I4_GIT_STATUS_RESPONSE_FD}<&-
  kill -TERM $pid 2>/dev/null
  # A stopped process cannot handle TERM until continued during cleanup.
  kill -CONT $pid 2>/dev/null
}

if (( $+commands[git] )); then
  _i4_git_status_start
  add-zsh-hook precmd _i4_git_status_precmd
  add-zsh-hook zshexit _i4_git_status_stop
fi
