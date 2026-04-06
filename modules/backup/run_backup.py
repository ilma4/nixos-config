import json

from common import BackupError
from common import ensure_matching_chunker
from common import ensure_repo_ready
from common import init_repo
from common import log
from common import repo_location
from common import repo_name
from common import repo_password_file
from common import run_restic

LOCAL_REPO_LABEL = "local repo"


def main(config_file: str, restic_exe: str) -> int:
    with open(config_file, encoding="utf-8") as file:
        config = json.load(file)

    backup_paths = [str(path) for path in config.get("paths", [])]
    if not backup_paths:
        raise BackupError("no backup paths configured")

    local_repo = config.get("localRepo")
    if local_repo is None:
        raise BackupError("localRepo must be configured when i4.backup.enable = true")

    remote_repos = list(config.get("remoteRepos") or [])
    if ensure_repo_ready(local_repo, LOCAL_REPO_LABEL, restic_exe) == "missing":
        init_source_repo = None
        for remote_repo in remote_repos:
            label = f"remote repo {repo_name(remote_repo)}"
            if ensure_repo_ready(remote_repo, label, restic_exe) == "ready":
                init_source_repo = remote_repo
                break

        init_repo(local_repo, LOCAL_REPO_LABEL, restic_exe, init_source_repo)

    local_password_file = repo_password_file(local_repo)

    log("running restic backup into the local repository")
    run_restic(
        local_repo,
        local_password_file,
        ["backup", *backup_paths],
        restic_exe,
    )

    for remote_repo in remote_repos:
        label = f"remote repo {repo_name(remote_repo)}"
        if ensure_repo_ready(remote_repo, label, restic_exe) == "missing":
            init_repo(remote_repo, label, restic_exe, local_repo)

        ensure_matching_chunker(local_repo, remote_repo, restic_exe)

        log(f"copying snapshots from local repo to {label}")
        run_restic(
            remote_repo,
            repo_password_file(remote_repo),
            [
                "copy",
                "--from-repo",
                repo_location(local_repo),
                "--from-password-file",
                local_password_file,
            ],
            restic_exe,
            extra_repos=[local_repo],
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
