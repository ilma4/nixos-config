import json
import subprocess
import sys
from dataclasses import dataclass, field, replace


@dataclass
class Repo:
    location: str
    passwordFile: str
    name: str = "local"
    oldPasswordFile: str | None = None
    extraResticArgs: list[str] = field(default_factory=list)
    init: bool = True

    @classmethod
    def from_dict(cls, data):
        return cls(
            location=str(data["location"]),
            passwordFile=str(data["passwordFile"]),
            name=str(data.get("name") or "local"),
            oldPasswordFile=str(data["oldPasswordFile"])
            if data.get("oldPasswordFile")
            else None,
            extraResticArgs=[str(arg) for arg in (data.get("extraResticArgs") or [])],
            init=bool(data.get("init", True)),
        )

    def with_old_password(self):
        if not self.oldPasswordFile:
            raise RuntimeError(f"oldPasswordFile is not configured for {self.name}")
        return replace(self, passwordFile=self.oldPasswordFile, oldPasswordFile=None)

    def from_args(self):
        return ["--from-repo", self.location, "--from-password-file", self.passwordFile]

    def run_restic(self, *args, capture_output=False, check=True):
        cmd = ["restic", "--repo", self.location, "--password-file", self.passwordFile]
        cmd += self.extraResticArgs + list(args)
        return subprocess.run(
            cmd, capture_output=capture_output, check=check, text=True
        )

    def run_restic_json(self, *args):
        return json.loads(self.run_restic(*args, capture_output=True).stdout)

    def read_repo_chunker(self):
        config = self.run_restic_json("cat", "config", "--json")
        return config.get("chunker_polynomial") or config.get("chunkerPolynomial")

    def ensure_matching_chunker(self, other):
        chunker, other_chunker = self.read_repo_chunker(), other.read_repo_chunker()
        if None in (chunker, other_chunker):
            raise RuntimeError(
                "unable to read chunker parameters from one of the restic repository "
                "configs"
            )
        if chunker == other_chunker:
            return
        raise RuntimeError(
            "chunker parameters differ between "
            f"{self.name} and {other.name}, refusing to run restic copy"
        )

    def status(self):
        return self.run_restic("cat", "config", check=False).returncode

    def access(self, label):
        status = self.status()
        if status == 0:
            return "ready", self
        if status == MISSING_REPO_EXIT_CODE:
            return "missing", None
        if status != BAD_PASSWORD_EXIT_CODE:
            raise RuntimeError(
                f"{label}: failed to access the repository with the current password file "
                f"(restic exit code {status})"
            )
        old_repo = self.with_old_password()
        old_status = old_repo.status()
        if old_status == 0:
            return "needs-rotation", old_repo
        if old_status == MISSING_REPO_EXIT_CODE:
            return "missing", None
        raise RuntimeError(
            f"{label}: oldPasswordFile also failed while checking the "
            f"repository (restic exit code {old_status})"
        )

    def rotate_key_if_needed(self, label):
        status = self.status()
        if status == 0:
            log(f"{label}: current password already works, skipping key rotation")
            return
        if status != BAD_PASSWORD_EXIT_CODE:
            raise RuntimeError(
                f"{label}: failed to access the repository with the current password file "
                f"(restic exit code {status})"
            )
        with_old_password = self.with_old_password()
        old_status = with_old_password.status()
        if old_status != 0:
            raise RuntimeError(
                f"{label}: oldPasswordFile failed while checking the repository "
                f"(restic exit code {old_status})"
            )
        log(f"{label}: rotating restic key to the current password file")
        with_old_password.run_restic(
            "key", "add", "--new-password-file", self.passwordFile
        )
        for key in self.run_restic_json("key", "list", "--json"):
            if not key.get("current"):
                self.run_restic("key", "remove", str(key["id"]))

    def init_repo(self, label, source_repo=None):
        if not self.init:
            raise RuntimeError(f"{label} is missing and init = false")
        args = ["init"]
        log(f"{label}: initializing repository")
        if source_repo is not None:
            log(f"{label}: copying chunker params from {source_repo.name}")
            args += ["--copy-chunker-params", *source_repo.from_args()]
        self.run_restic(*args)


def load_config(config_file):
    with open(config_file, encoding="utf-8") as file:
        return json.load(file)


def log(message):
    print(f"i4-backup: {message}", file=sys.stderr)


MISSING_REPO_EXIT_CODE = 10
BAD_PASSWORD_EXIT_CODE = 12
