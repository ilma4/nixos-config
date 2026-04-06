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

    def from_args(self) -> list[str]:
        return ["--from-repo", self.location, "--from-password-file", self.passwordFile]

    def run_restic(
        self,
        *args: str,
        password_file: str | None = None,
        capture_output: bool = False,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        cmd = [
            "restic",
            "--repo",
            self.location,
            "--password-file",
            self.passwordFile if password_file is None else password_file,
            *self.extraResticArgs,
        ]

        return subprocess.run(
            [*cmd, *args], capture_output=capture_output, check=check, text=True
        )

    def run_restic_json(self, *args: str) -> Any:
        result = self.run_restic(*args, capture_output=True)
        return json.loads(result.stdout)

    def read_repo_chunker(self) -> str | None:
        repo_config = self.run_restic_json("cat", "config", "--json")
        for key in ("chunker_polynomial", "chunkerPolynomial"):
            value = repo_config.get(key)
            if value not in (None, ""):
                return str(value)
        return None

    def ensure_matching_chunker(self, other_repo: "Repo") -> None:
        repo_chunker = self.read_repo_chunker()
        other_repo_chunker = other_repo.read_repo_chunker()

        if repo_chunker is None or other_repo_chunker is None:
            raise BackupError(
                "unable to read chunker parameters from one of the restic repository "
                "configs"
            )

        if repo_chunker == other_repo_chunker:
            return

        raise BackupError(
            "chunker parameters differ between "
            f"{self.name} and {other_repo.name}, refusing to run restic "
            "copy"
        )

    def probe_repo_status(self, *, password_file: str | None = None) -> int:
        return self.run_restic(
            "cat", "config", password_file=password_file, check=False
        ).returncode

    def rotate_repo_password(self, label: str, old_password_file: str) -> None:
        log(f"{label}: rotating restic key to the current password file")
        self.run_restic(
            "key",
            "add",
            "--new-password-file",
            self.passwordFile,
            password_file=old_password_file,
        )

        keys = self.run_restic_json("key", "list", "--json")

        for key in [k for k in keys if not k.get("current")]:
            self.run_restic("key", "remove", str(key["id"]))

    def ensure_repo_ready(self, label: str) -> str:
        current_status = self.probe_repo_status()
        if current_status in (0, MISSING_REPO_EXIT_CODE):
            return "ready" if current_status == 0 else "missing"
        if current_status != BAD_PASSWORD_EXIT_CODE:
            raise BackupError(
                f"{label}: failed to access the repository with the current password "
                f"file (restic exit code {current_status})"
            )

        old_password_file = self.oldPasswordFile
        if old_password_file is None:
            raise BackupError(
                f"{label}: current password file cannot unlock the repository "
                "and no oldPasswordFile is configured"
            )

        old_status = self.probe_repo_status(password_file=old_password_file)
        if old_status == 0:
            self.rotate_repo_password(label, old_password_file)
            return "ready"
        if old_status == MISSING_REPO_EXIT_CODE:
            return "missing"

        raise BackupError(
            f"{label}: oldPasswordFile also failed while checking the "
            f"repository (restic exit code {old_status})"
        )

    def init_repo(self, label: str, source_repo: Repo | None = None) -> None:
        if not self.init:
            raise BackupError(f"{label} is missing and init = false")

        location_path = Path(self.location)
        if location_path.is_absolute():
            location_path.mkdir(parents=True, exist_ok=True)

        init_args = ["init"]
        log(f"{label}: initializing repository")

        if source_repo is not None:
            log(f"{label}: initializing repository with copied chunker params")
            init_args += ["--copy-chunker-params", *source_repo.from_args()]

        self.run_restic(*init_args)


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
