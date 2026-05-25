import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";

const title = process.env.PI_NOTIFY_TITLE ?? "Pi";
const body = process.env.PI_NOTIFY_BODY ?? "Agent finished";

function run(cmd: string, args: string[]) {
  execFile(cmd, args, { stdio: "ignore" }, () => {});
}

function osc777(title: string, body: string) {
  // Ghostty, iTerm2, WezTerm, rxvt-unicode
  process.stdout.write(`\x1b]777;notify;${title};${body}\x07`);
}

function notify(title: string, body: string) {
  switch (process.platform) {
    case "darwin":
      run("osascript", [
        "-e",
        `display notification ${JSON.stringify(body)} with title ${JSON.stringify(title)} sound name "default"`,
      ]);
      break;

    case "linux":
      run("notify-send", [title, body]);
      break;

    case "win32":
      run("powershell.exe", [
        "-NoProfile",
        "-Command",
        `
                Add-Type -AssemblyName System.Windows.Forms;
                $n = New-Object System.Windows.Forms.NotifyIcon;
                $n.Icon = [System.Drawing.SystemIcons]::Information;
                $n.BalloonTipTitle = ${JSON.stringify(title)};
                $n.BalloonTipText = ${JSON.stringify(body)};
                $n.Visible = true;
                $n.ShowBalloonTip(3000);
                Start-Sleep -Milliseconds 3500;
                $n.Dispose();
              `,
      ]);
      break;

    default:
      osc777(title, body);
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("agent_end", async () => {
    notify(title, body);
  });
}
