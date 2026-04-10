from common import Repo, load_config

def main(config_file):
    config = load_config(config_file)
    Repo.from_dict(config.get("localRepo")).rotate_key_if_needed("local repo")
    for repo_data in config.get("remoteRepos") or []:
        repo = Repo.from_dict(repo_data)
        repo.rotate_key_if_needed(f"remote repo {repo.name}")
    return 0
