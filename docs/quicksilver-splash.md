# Splash inference on Quicksilver

Splash runs in `malakhov`'s macOS login session. It loads Qwen3.8-27B,
its vision projector, and its DFlash2 draft offline from
`/Users/malakhov/llama-cpp/models`. A small Rust proxy starts Splash on demand
and stops the entire Splash process after 10 minutes without active requests.
The first request after idle waits for model warm-up, which can take around
100 seconds. `/health`, `/ready`, `/status`, and `/metrics` do not wake Splash
or reset the timer. While Splash is down, `/health` reports the proxy is up
and the other three return HTTP 503.

| Client | OpenAI-compatible base URL |
| --- | --- |
| On Quicksilver | `http://127.0.0.1:8080/v1` |
| On the tailnet | `http://quicksilver.tail09544e.ts.net:8080/v1` |

Use `Qwen3.8` as the model ID. Check `GET /v1/models` at either address.
The proxy listens only on loopback, and Splash listens on a private Unix
socket; Tailscale Serve forwards port 8080 within
the tailnet. There is no public or LAN listener. The API has no separate
API-key check, so remote access follows the tailnet policy.

Logs are in `~/Library/Logs/splash.log` and
`~/Library/Logs/splash-tailscale.log`. Run `tailscale serve status --json` on
Quicksilver to check the forwarder.
