import json

from common import (
    BackupError,
    Repo,
    ensure_matching_chunker,
    ensure_repo_ready,
    init_repo,
    log,
    run_restic,
)

LOCAL_REPO_LABEL = "local repo"


def main(config_file: str, restic_exe: str) -> int:
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
    if ensure_repo_ready(local_repo, LOCAL_REPO_LABEL, restic_exe) == "missing":
        init_source_repo = None
        for remote_repo in remote_repos:
            label = f"remote repo {remote_repo.name}"
            if ensure_repo_ready(remote_repo, label, restic_exe) == "ready":
                init_source_repo = remote_repo
                break

        init_repo(local_repo, LOCAL_REPO_LABEL, restic_exe, init_source_repo)

    local_password_file = local_repo.passwordFile

    log("running restic backup into the local repository")
    run_restic(
        local_repo,
        local_password_file,
        ["backup", *backup_paths],
        restic_exe,
    )

    for remote_repo in remote_repos:
        label = f"remote repo {remote_repo.name}"
        if ensure_repo_ready(remote_repo, label, restic_exe) == "missing":
            init_repo(remote_repo, label, restic_exe, local_repo)

        ensure_matching_chunker(
            local_repo,
            remote_repo,
            restic_exe,
        )

        log(f"copying snapshots from local repo to {label}")
        run_restic(
            remote_repo,
            remote_repo.passwordFile,
            [
                "copy",
                "--from-repo",
                local_repo.location,
                "--from-password-file",
                local_password_file,
            ],
            restic_exe,
        )

    keep_within = config.get("keepWithin")
    if keep_within:
        log(f"running local retention with --keep-within {keep_within}")
        run_restic(
            local_repo,
            local_password_file,
            ["forget", "--keep-within", str(keep_within)],
            restic_exe,
        )

    return 0
