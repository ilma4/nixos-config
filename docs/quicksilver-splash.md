# Splash inference on Quicksilver

Splash runs in `malakhov`'s macOS login session. It loads Qwen3.8-27B,
its vision projector, and its DFlash2 draft offline from
`/Users/malakhov/llama-cpp/models`. After 10 minutes without requests it
releases the model's memory, then reloads it on demand.

| Client | OpenAI-compatible base URL |
| --- | --- |
| On Quicksilver | `http://127.0.0.1:8080/v1` |
| On the tailnet | `http://quicksilver.tail09544e.ts.net:8080/v1` |

Use `Qwen3.8` as the model ID. Check `GET /v1/models` at either address.
Splash listens only on loopback; Tailscale Serve forwards port 8080 within
the tailnet. There is no public or LAN listener. The API has no separate
API-key check, so remote access follows the tailnet policy.

Logs are in `~/Library/Logs/splash.log` and
`~/Library/Logs/splash-tailscale.log`. Run `tailscale serve status --json` on
Quicksilver to check the forwarder.
