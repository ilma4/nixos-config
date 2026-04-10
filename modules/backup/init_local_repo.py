from common import Repo, load_config, log


def main(config_file):
    config = load_config(config_file)
    local_repo = Repo.from_dict(config.get("localRepo"))
    if local_repo.access("local repo")[0] != "missing":
        log("local repo: already exists, skipping initialization")
        return 0
    source_repo = None
    for repo_data in config.get("remoteRepos") or []:
        remote_repo = Repo.from_dict(repo_data)
        label = f"remote repo {remote_repo.name}"
        state, source_repo = remote_repo.access(label)
        if state != "missing":
            break
    local_repo.init_repo("local repo", source_repo)
    return 0
