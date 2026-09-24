# Run as a long-lived coprocess. The interactive shell sends NUL-delimited
# requests; only this process launches Git.
emulate -R zsh -o no_aliases

function _i4_format_git_status() {
  local porcelain=$1 dir=$2 line xy branch= oid= upstream= tag= action= git_dir= remote=
  local -i ahead=0 behind=0 conflicted=0 staged=0 unstaged=0 untracked=0 stashed=0

  while IFS= read -r line; do
    case $line in
      '# branch.oid '*) oid=${line#\# branch.oid } ;;
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.upstream '*) upstream=${line#\# branch.upstream } ;;
      '# branch.ab '*)
        local tracking=${line#\# branch.ab }
        ahead=${${tracking%% *}#+}
        behind=${${tracking##* }#-}
        ;;
      '# stash '*) stashed=${line#\# stash } ;;
      '1 '*|'2 '*)
        xy=${line[3,4]}
        [[ ${xy[1]} == . ]] || (( ++staged ))
        [[ ${xy[2]} == . ]] || (( ++unstaged ))
        ;;
      'u '*) (( ++conflicted )) ;;
      '? '*) (( ++untracked )) ;;
    esac
  done <<< "$porcelain"

  [[ $branch == '(detached)' ]] && branch=
  if [[ -n $upstream ]]; then
    remote=$(command git -C "$dir" config --get "branch.$branch.remote" 2>/dev/null)
    [[ -n $remote && $remote != . && $upstream == "$remote/"* ]] && upstream=${upstream#"$remote/"}
  fi
  tag=$(command git -C "$dir" tag --points-at HEAD --sort=refname 2>/dev/null)
  tag=${tag##*$'\n'}

  git_dir=$(command git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)
  if [[ -n $git_dir ]]; then
    if [[ -d $git_dir/rebase-merge || -d $git_dir/rebase-apply ]]; then
      action=rebase
    elif [[ -e $git_dir/MERGE_HEAD ]]; then
      action=merge
    elif [[ -e $git_dir/CHERRY_PICK_HEAD ]]; then
      action=cherry-pick
    elif [[ -e $git_dir/REVERT_HEAD ]]; then
      action=revert
    elif [[ -e $git_dir/BISECT_LOG ]]; then
      action=bisect
    fi
  fi
  # Powerlevel10k's VCS renderer consumes these fields. Ref names cannot
  # contain the ASCII unit separator, so empty fields survive the protocol.
  local -a fields=("$branch" "$upstream" "$action" "$staged" "$unstaged"
    "$untracked" "$conflicted" "$ahead" "$behind" "$stashed" "$tag" "$oid")
  REPLY=${(pj:\x1f:)fields}
}

zmodload zsh/parameter
typeset -a previous_git_names=(${(k)parameters[(I)GIT_*]})
typeset id= dir= request_path= count= name= value= porcelain=
while IFS= read -r -d '' id; do
  IFS= read -r -d '' dir || break
  IFS= read -r -d '' request_path || break
  IFS= read -r -d '' count || break

  for name in "${previous_git_names[@]}"; do
    unset "$name"
  done
  previous_git_names=()
  for (( i = 0; i < count; ++i )); do
    IFS= read -r -d '' name || exit 0
    IFS= read -r -d '' value || exit 0
    [[ $name == GIT_* ]] || exit 1
    export "$name=$value"
    previous_git_names+=("$name")
  done
  export PATH=$request_path

  if porcelain=$(GIT_OPTIONAL_LOCKS=0 command git -C "$dir" status --porcelain=v2 --branch --show-stash 2>/dev/null); then
    _i4_format_git_status "$porcelain" "$dir"
  else
    REPLY=
  fi
  print -rn -- "$id:$REPLY"$'\0'
done
