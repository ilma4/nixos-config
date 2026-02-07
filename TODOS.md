# Constants!

Define more constants to simplify secrets/path/locations etc. management

- Use constants to update the password on the restic repositories
  - activation script, that checks if the current password is working, otherwise do not apply the update
  - similar thing can be used for other "statefull services"



# /update-service command

Create a slash command for codex/claude codex/gemini so that they can update my services. I.e.:

They have to search for the newer version of the service, find the docker-compose.yml file or the docker container version and update my config to match them.
