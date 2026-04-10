from common import Repo, load_config, log


def main(config_file):
    config = load_config(config_file)
    backup_paths = [str(path) for path in config.get("paths") or []]
    if not backup_paths:
        raise ValueError("no backup paths configured")
    local_repo = Repo.from_dict(config.get("localRepo"))
    log("running restic backup into the local repository")
    local_repo.run_restic("backup", *backup_paths)
    for repo_data in config.get("remoteRepos") or []:
        remote_repo = Repo.from_dict(repo_data)
        label = f"remote repo {remote_repo.name}"
        local_repo.ensure_matching_chunker(remote_repo)
        log(f"copying snapshots from local repo to {label}")
        remote_repo.run_restic("copy", *local_repo.from_args())
    if keep_within := config.get("keepWithin"):
        log(f"running local retention with --keep-within {keep_within}")
        local_repo.run_restic("forget", "--keep-within", str(keep_within))
        local_repo.run_restic("prune")
    return 0
