import json

from common import (
    BackupError,
    Repo,
    log,
)

LOCAL_REPO_LABEL = "local repo"


def main(config_file: str) -> int:
    with open(config_file, encoding="utf-8") as file:
        config = json.load(file)

    backup_paths = [str(path) for path in config.get("paths", [])]
    if not backup_paths:
        raise BackupError("no backup paths configured")

    local_repo_data = config.get("localRepo")
    local_repo = Repo.from_dict(local_repo_data)

    remote_repos = [
        Repo.from_dict(repo_data) for repo_data in (config.get("remoteRepos") or [])
    ]
    if local_repo.ensure_repo_ready(LOCAL_REPO_LABEL) == "missing":
        init_source_repo = None
        for remote_repo in remote_repos:
            label = f"remote repo {remote_repo.name}"
            if remote_repo.ensure_repo_ready(label) == "ready":
                init_source_repo = remote_repo
                break

        local_repo.init_repo(LOCAL_REPO_LABEL, init_source_repo)

    local_password_file = local_repo.passwordFile

    log("running restic backup into the local repository")
    local_repo.run_restic(
        ["backup", *backup_paths],
    )

    for remote_repo in remote_repos:
        label = f"remote repo {remote_repo.name}"
        if remote_repo.ensure_repo_ready(label) == "missing":
            remote_repo.init_repo(label, local_repo)

        local_repo.ensure_matching_chunker(remote_repo)

        log(f"copying snapshots from local repo to {label}")
        remote_repo.run_restic(
            [
                "copy",
                "--from-repo",
                local_repo.location,
                "--from-password-file",
                local_password_file,
            ],
        )

    keep_within = config.get("keepWithin")
    if keep_within:
        log(f"running local retention with --keep-within {keep_within}")
        local_repo.run_restic(
            ["forget", "--keep-within", str(keep_within)],
        )

    return 0
