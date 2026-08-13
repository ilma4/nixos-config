{...}: {
  # System-wide LaunchAgents are loaded in every logged-in user's launchd domain.
  launchd.agents.clean-toolbox-download-cache = {
    script = ''
      set -euo pipefail

      /bin/rm -rf ~/Library/Caches/JetBrains/Toolbox/download
    '';

    serviceConfig.StartCalendarInterval = [
      {
        Hour = 4;
        Minute = 0;
      }
    ];
  };
}
