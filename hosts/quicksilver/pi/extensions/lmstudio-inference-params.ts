import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const LMSTUDIO_MODELS = new Set(["qwen3.6-35b-a3b"]);

export default function (pi: ExtensionAPI) {
  pi.on("before_provider_request", (event) => {
    const payload = event.payload as Record<string, unknown>;

    if (typeof payload.model !== "string") return;
    if (!LMSTUDIO_MODELS.has(payload.model)) return;

    return {
      ...payload,
      temperature: 0.6,
      top_p: 0.95,
      top_k: 20,
      min_p: 0.0,
      presence_penalty: 0.0,
      repetition_penalty: 1.0
    };
  });
}
