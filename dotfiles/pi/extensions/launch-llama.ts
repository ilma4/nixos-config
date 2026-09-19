import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { stream, streamSimple } from "@earendil-works/pi-ai/compat";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const ANDROID_VOLUME = "/Volumes/Android";
const MODELS_DIR = join(ANDROID_VOLUME, "llama-cpp");
const SERVER_URL = "http://127.0.0.1:7777";
const INFERENCE_URL = `${SERVER_URL}/v1`;
const SERVER_SCRIPT = process.env.PI_LLAMA_SERVER_SCRIPT?.trim() || join(homedir(), ".local/bin/run-llama-server.sh");
const PROVIDER_ID = "llama.cpp";
const MODEL_ID = "Qwen3.8-27B-UD-Q6_K_XL";
const SERVER_START_TIMEOUT_MS = 60_000;
const MODEL_LOAD_TIMEOUT_MS = 10 * 60_000;

type CatalogEntry = {
	id: string;
	status: {
		value: string;
		failed?: boolean;
		exit_code?: number;
	};
	meta?: Record<string, unknown>;
	architecture?: Record<string, unknown>;
};

let models: Model<"openai-completions">[] = [];
let serverStart: Promise<void> | undefined;

function asRecord(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: undefined;
}

async function request(path: string, signal: AbortSignal, body?: { model: string }): Promise<unknown> {
	const response = await fetch(`${SERVER_URL}${path}`, {
		method: body ? "POST" : "GET",
		headers: body ? { "content-type": "application/json" } : undefined,
		body: JSON.stringify(body),
		signal,
	});
	const payload: unknown = await response.json().catch(() => undefined);

	if (!response.ok) {
		const error = asRecord(payload)?.error;
		const message = asRecord(error)?.message;
		throw new Error(typeof message === "string" ? message
			: typeof error === "string" ? error : `llama.cpp returned HTTP ${response.status}`);
	}
	return payload;
}

async function listModels(signal: AbortSignal, reload = false): Promise<CatalogEntry[]> {
	const data = asRecord(await request(`/models${reload ? "?reload=1" : ""}`, signal))?.data;
	if (!Array.isArray(data) || !data.every((value: unknown): value is CatalogEntry => {
		const entry = asRecord(value);
		return typeof entry?.id === "string" && typeof asRecord(entry.status)?.value === "string";
	})) {
		throw new Error("llama.cpp returned an invalid model catalog");
	}
	return data;
}

function serverIsReady(): Promise<boolean> {
	return fetch(`${SERVER_URL}/health`, { signal: AbortSignal.timeout(1_000) })
		.then((response) => response.ok, () => false);
}

async function startServer(): Promise<void> {
	if (await serverIsReady()) return;
	if (!existsSync(SERVER_SCRIPT)) throw new Error(`llama server script not found: ${SERVER_SCRIPT}`);

	const child = spawn(SERVER_SCRIPT, [MODELS_DIR], { detached: true, stdio: "ignore" });
	child.unref();
	let childError: Error | undefined;

	child.once("error", (error) => {
		childError = error;
	});
	child.once("exit", (code, signal) => {
		childError ??= new Error(
			`llama server exited before becoming ready (code ${code ?? "none"}, signal ${signal ?? "none"})`,
		);
	});

	const deadline = Date.now() + SERVER_START_TIMEOUT_MS;
	while (Date.now() < deadline) {
		if (await serverIsReady()) return;
		if (childError) throw childError;
		await sleep(250);
	}

	throw new Error(`llama.cpp server did not become ready within ${SERVER_START_TIMEOUT_MS / 1_000} seconds`);
}

function isLoaded({ status }: CatalogEntry): boolean {
	return ["loaded", "sleeping"].includes(status.value);
}

function isFailed({ status }: CatalogEntry): boolean {
	return status.failed === true || status.value === "failed";
}

async function loadModel(target: CatalogEntry, signal: AbortSignal): Promise<CatalogEntry> {
	if (isLoaded(target)) return target;
	if (isFailed(target)) throw new Error(`Model ${target.id} is already in a failed state`);

	if (target.status.value !== "loading") {
		await request("/models/load", signal, { model: target.id });
	}

	while (true) {
		signal.throwIfAborted();
		const current = (await listModels(signal)).find((entry) => entry.id === target.id);
		if (!current) throw new Error(`Model ${target.id} disappeared from the llama.cpp catalog`);
		if (isLoaded(current)) return current;
		if (isFailed(current)) {
			const exitCode = current.status.exit_code;
			throw new Error(`Model ${target.id} failed to load${exitCode === undefined ? "" : ` (exit code ${exitCode})`}`);
		}
		await sleep(250);
	}
}

function toPiModel({ id, architecture, meta }: CatalogEntry): Model<"openai-completions"> {
	const modalities = architecture?.input_modalities;
	const reported = meta?.n_ctx ?? meta?.n_ctx_train;
	const window = typeof reported === "number" && Number.isFinite(reported) && reported > 0 ? reported : 128_000;

	return {
		id,
		name: id,
		api: "openai-completions",
		provider: PROVIDER_ID,
		baseUrl: INFERENCE_URL,
		reasoning: false,
		input: Array.isArray(modalities) && modalities.includes("image") ? ["text", "image"] : ["text"],
		cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0},
		contextWindow: window,
		maxTokens: window,
		compat: {
			supportsStore: false,
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			supportsUsageInStreaming: true,
			supportsStrictMode: false,
			maxTokensField: "max_tokens",
		},
	};
}

export default function launchLlamaExtension(pi: ExtensionAPI): void {
	pi.registerProvider({
		id: PROVIDER_ID,
		name: "llama.cpp",
		baseUrl: INFERENCE_URL,
		auth: {
			apiKey: {
				name: "local llama.cpp server",
				check: async () => ({type: "api_key", source: "local server"}),
				resolve: async () => ({
					auth: {apiKey: "local", baseUrl: INFERENCE_URL},
					env: {LLAMA_BASE_URL: SERVER_URL},
					source: "local server",
				}),
			},
		},
		getModels: () => models,
		refreshModels: async ({allowNetwork, signal, publish}) => {
			if (!allowNetwork || signal.aborted) return;
			const catalog = await listModels(signal);
			if (signal.aborted) return;
			await publish({update: () => {
				models = catalog.filter(isLoaded).map(toPiModel);
			}});
		},
		stream: (model, context, options) => stream(model, context, options as Parameters<typeof stream>[2]),
		streamSimple,
	});

	pi.registerCommand("launch-llama", {
		description: `Start llama.cpp and select ${MODEL_ID}`,
		handler: async (_args, ctx) => {
			try {
				if (!existsSync(ANDROID_VOLUME)) throw new Error(`${ANDROID_VOLUME} does not exist`);
				if (!existsSync(MODELS_DIR)) throw new Error(`llama.cpp models directory not found: ${MODELS_DIR}`);

				ctx.ui.notify("Starting llama.cpp server…", "info");
				await (serverStart ??= startServer().finally(() => { serverStart = undefined; }));

				const loadSignal = AbortSignal.timeout(MODEL_LOAD_TIMEOUT_MS);
				const catalog = await listModels(loadSignal, true);
				const target = catalog.find(({ id }) => id === MODEL_ID)
					?? catalog.find(({ id }) => id.split("/").at(-1)?.replace(/\.gguf$/iu, "") === MODEL_ID);
				if (!target) throw new Error(`Model ${MODEL_ID} was not found in ${MODELS_DIR}`);

				ctx.ui.notify(`Loading ${target.id}…`, "info");
				const loaded = await loadModel(target, loadSignal);

				const refresh = await ctx.modelRegistry.refresh({
					providers: [PROVIDER_ID],
					allowNetwork: true,
					force: true,
					signal: AbortSignal.timeout(30_000),
				});
				if (refresh.aborted) throw new Error("Timed out while refreshing the llama.cpp model catalog");
				const refreshError = refresh.errors.get(PROVIDER_ID);
				if (refreshError) throw refreshError;

				const model = ctx.modelRegistry.find(PROVIDER_ID, loaded.id);
				if (!model) throw new Error(`Loaded model ${loaded.id} is not available to pi`);
				if (!(await pi.setModel(model))) throw new Error("Could not authenticate with the local llama.cpp provider");

				ctx.ui.notify(`Selected llama.cpp/${loaded.id}`, "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				console.error(`/launch-llama: ${message}`);
				ctx.ui.notify(message, "error");
			}
		},
	});
}
