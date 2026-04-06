import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

Repo = dict[str, Any]
MISSING_REPO_EXIT_CODE = 10
BAD_PASSWORD_EXIT_CODE = 12


class BackupError(Exception):
    pass


def log(message: str) -> None:
    print(f"i4-backup: {message}", file=sys.stderr)


def log_error(message: str) -> None:
    print(f"i4-backup: ERROR: {message}", file=sys.stderr)


def run_cli(main_fn: Callable[[], int]) -> int:
    try:
        return main_fn()
    except BackupError as exc:
        log_error(str(exc))
    except json.JSONDecodeError as exc:
        log_error(f"invalid JSON data: {exc}")
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        if stderr:
            log_error(stderr)
        return exc.returncode or 1
    return 1


def repo_name(repo: Repo) -> str:
    return str(repo.get("name") or "local")


def repo_location(repo: Repo) -> str:
    return str(repo["location"])


def repo_password_file(repo: Repo) -> str:
    return str(repo["passwordFile"])


def repo_old_password_file(repo: Repo) -> str | None:
    value = repo.get("oldPasswordFile")
    return None if value in (None, "") else str(value)


def run_restic(
    repo: Repo,
    password_file: str,
    args: list[str],
    restic_exe: str,
    *,
    extra_repos: list[Repo] | None = None,
    capture_output: bool = False,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        restic_exe,
        "--no-cache",
        "--repo",
        repo_location(repo),
        "--password-file",
        password_file,
    ]
    for current_repo in (repo, *(extra_repos or [])):
        cmd.extend(str(arg) for arg in (current_repo.get("extraResticArgs") or []))

    return subprocess.run(
        cmd + args,
        capture_output=capture_output,
        check=check,
        text=True,
    )


def run_restic_json(
    repo: Repo,
    password_file: str,
    args: list[str],
    restic_exe: str,
    *,
    extra_repos: list[Repo] | None = None,
) -> Any:
    result = run_restic(
        repo,
        password_file,
        args,
        restic_exe,
        extra_repos=extra_repos,
        capture_output=True,
    )
    return json.loads(result.stdout)


def read_repo_chunker(repo: Repo, restic_exe: str) -> str | None:
    repo_config = run_restic_json(
        repo,
        repo_password_file(repo),
        ["cat", "config", "--json"],
        restic_exe,
    )
    for key in ("chunker_polynomial", "chunkerPolynomial"):
        value = repo_config.get(key)
        if value not in (None, ""):
            return str(value)
    return None


def ensure_matching_chunker(repo_a: Repo, repo_b: Repo, restic_exe: str) -> None:
    repo_a_chunker = read_repo_chunker(repo_a, restic_exe)
    repo_b_chunker = read_repo_chunker(repo_b, restic_exe)

    if repo_a_chunker is None or repo_b_chunker is None:
        raise BackupError(
            "unable to read chunker parameters from one of the restic repository "
            "configs"
        )

    if repo_a_chunker == repo_b_chunker:
        return

    raise BackupError(
        "chunker parameters differ between "
        f"{repo_name(repo_a)} and {repo_name(repo_b)}, refusing to run restic "
        "copy"
    )


def probe_repo_status(
    repo: Repo,
    password_file: str,
    restic_exe: str,
) -> int:
    return run_restic(
        repo,
        password_file,
        ["cat", "config"],
        restic_exe,
        check=False,
    ).returncode


def rotate_repo_password(
    repo: Repo,
    label: str,
    old_password_file: str,
    restic_exe: str,
) -> None:
    new_password_file = repo_password_file(repo)

    log(f"{label}: rotating restic key to the current password file")
    run_restic(
        repo,
        old_password_file,
        ["key", "add", "--new-password-file", new_password_file],
        restic_exe,
    )

    keys = run_restic_json(
        repo,
        new_password_file,
        ["key", "list", "--json"],
        restic_exe,
    )

    for key in keys:
        if key.get("current") is True:
            continue

        run_restic(
            repo,
            new_password_file,
            ["key", "remove", str(key["id"])],
            restic_exe,
        )


def ensure_repo_ready(
    repo: Repo,
    label: str,
    restic_exe: str,
) -> str:
    current_password_file = repo_password_file(repo)
    current_status = probe_repo_status(repo, current_password_file, restic_exe)
    if current_status in (0, MISSING_REPO_EXIT_CODE):
        return "ready" if current_status == 0 else "missing"
    if current_status != BAD_PASSWORD_EXIT_CODE:
        raise BackupError(
            f"{label}: failed to access the repository with the current password "
            f"file (restic exit code {current_status})"
        )

    old_password_file = repo_old_password_file(repo)
    if old_password_file is None:
        raise BackupError(
            f"{label}: current password file cannot unlock the repository "
            "and no oldPasswordFile is configured"
        )

    old_status = probe_repo_status(repo, old_password_file, restic_exe)
    if old_status == 0:
        rotate_repo_password(repo, label, old_password_file, restic_exe)
        return "ready"
    if old_status == MISSING_REPO_EXIT_CODE:
        return "missing"

    raise BackupError(
        f"{label}: oldPasswordFile also failed while checking the "
        f"repository (restic exit code {old_status})"
    )


def init_repo(
    repo: Repo,
    label: str,
    restic_exe: str,
    source_repo: Repo | None = None,
) -> None:
    if not bool(repo.get("init", True)):
        raise BackupError(f"{label} is missing and init = false")

    location_path = Path(repo_location(repo))
    if location_path.is_absolute():
        location_path.mkdir(parents=True, exist_ok=True)

    init_args = ["init"]
    extra_repos = None
    log_message = f"{label}: initializing repository"

    if source_repo is not None:
        log_message = f"{label}: initializing repository with copied chunker params"
        init_args.extend(
            [
                "--copy-chunker-params",
                "--from-repo",
                repo_location(source_repo),
                "--from-password-file",
                repo_password_file(source_repo),
            ]
        )
        extra_repos = [source_repo]

    log(log_message)
    run_restic(
        repo,
        repo_password_file(repo),
        init_args,
        restic_exe,
        extra_repos=extra_repos,
    )
