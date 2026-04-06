import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


@dataclass
class Repo:
    location: str
    passwordFile: str
    name: str = "local"
    oldPasswordFile: str | None = None
    extraResticArgs: list[str] = field(default_factory=list)
    init: bool = True

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Repo":
        old_password_file = data.get("oldPasswordFile")
        return cls(
            location=str(data["location"]),
            passwordFile=str(data["passwordFile"]),
            name=str(data.get("name") or "local"),
            oldPasswordFile=None
            if old_password_file in (None, "")
            else str(old_password_file),
            extraResticArgs=[str(arg) for arg in (data.get("extraResticArgs") or [])],
            init=bool(data.get("init", True)),
        )


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


def run_restic(
    repo: Repo,
    password_file: str,
    args: list[str],
    *,
    capture_output: bool = False,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    cmd = [
        "restic",
        "--repo",
        repo.location,
        "--password-file",
        password_file,
        *repo.extraResticArgs,
    ]

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
) -> Any:
    result = run_restic(
        repo,
        password_file,
        args,
        capture_output=True,
    )
    return json.loads(result.stdout)


def read_repo_chunker(repo: Repo) -> str | None:
    repo_config = run_restic_json(
        repo,
        repo.passwordFile,
        ["cat", "config", "--json"],
    )
    for key in ("chunker_polynomial", "chunkerPolynomial"):
        value = repo_config.get(key)
        if value not in (None, ""):
            return str(value)
    return None


def ensure_matching_chunker(
    repo_a: Repo,
    repo_b: Repo,
) -> None:
    repo_a_chunker = read_repo_chunker(repo_a)
    repo_b_chunker = read_repo_chunker(repo_b)

    if repo_a_chunker is None or repo_b_chunker is None:
        raise BackupError(
            "unable to read chunker parameters from one of the restic repository "
            "configs"
        )

    if repo_a_chunker == repo_b_chunker:
        return

    raise BackupError(
        "chunker parameters differ between "
        f"{repo_a.name} and {repo_b.name}, refusing to run restic "
        "copy"
    )


def probe_repo_status(
    repo: Repo,
    password_file: str,
) -> int:
    return run_restic(
        repo,
        password_file,
        ["cat", "config"],
        check=False,
    ).returncode


def rotate_repo_password(
    repo: Repo,
    label: str,
    old_password_file: str,
) -> None:
    new_password_file = repo.passwordFile

    log(f"{label}: rotating restic key to the current password file")
    run_restic(
        repo,
        old_password_file,
        ["key", "add", "--new-password-file", new_password_file],
    )

    keys = run_restic_json(
        repo,
        new_password_file,
        ["key", "list", "--json"],
    )

    for key in keys:
        if key.get("current") is True:
            continue

        run_restic(
            repo,
            new_password_file,
            ["key", "remove", str(key["id"])],
        )


def ensure_repo_ready(
    repo: Repo,
    label: str,
) -> str:
    current_password_file = repo.passwordFile
    current_status = probe_repo_status(repo, current_password_file)
    if current_status in (0, MISSING_REPO_EXIT_CODE):
        return "ready" if current_status == 0 else "missing"
    if current_status != BAD_PASSWORD_EXIT_CODE:
        raise BackupError(
            f"{label}: failed to access the repository with the current password "
            f"file (restic exit code {current_status})"
        )

    old_password_file = repo.oldPasswordFile
    if old_password_file is None:
        raise BackupError(
            f"{label}: current password file cannot unlock the repository "
            "and no oldPasswordFile is configured"
        )

    old_status = probe_repo_status(repo, old_password_file)
    if old_status == 0:
        rotate_repo_password(repo, label, old_password_file)
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
    source_repo: Repo | None = None,
) -> None:
    if not repo.init:
        raise BackupError(f"{label} is missing and init = false")

    location_path = Path(repo.location)
    if location_path.is_absolute():
        location_path.mkdir(parents=True, exist_ok=True)

    init_args = ["init"]
    log_message = f"{label}: initializing repository"

    if source_repo is not None:
        log_message = f"{label}: initializing repository with copied chunker params"
        init_args.extend(
            [
                "--copy-chunker-params",
                "--from-repo",
                source_repo.location,
                "--from-password-file",
                source_repo.passwordFile,
            ]
        )

    log(log_message)
    run_restic(
        repo,
        repo.passwordFile,
        init_args,
    )
