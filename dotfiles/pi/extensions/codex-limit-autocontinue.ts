import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
	adapterForProvider,
	queryProviderUsage,
	resolveUsageAuth,
} from "../npm/node_modules/@narumitw/pi-usage/dist/index.ts";

const CODEX_PROVIDER = "openai-codex";
const LIMIT_MESSAGE = "Error: Codex error: The usage limit has been reached";
const STATUS_KEY = "codex-limit-autocontinue";
const FIVE_HOUR_MINUTES = 300;
const USAGE_QUERY_TIMEOUT_MS = 15_000;
const POLL_INTERVAL_MS = 60_000;
const RESUME_RETRY_INTERVAL_MS = 10_000;
const RESET_GRACE_MS = 10_000;
const MAX_TIMER_DELAY_MS = 2_147_000_000;

type UsageBucket = {
	id: string;
	unit: string;
	used?: number;
	remaining?: number;
	windowMinutes?: number;
	resetsAt?: number;
};

type UsageReport = { buckets: UsageBucket[] };
type UsageAdapter = { id: string };

const getUsageAdapter = adapterForProvider as unknown as (providerId: string) => UsageAdapter | undefined;
const getUsageAuth = resolveUsageAuth as unknown as (
	ctx: ExtensionContext,
	adapter: UsageAdapter,
) => Promise<unknown | undefined>;
const getUsageReport = queryProviderUsage as unknown as (
	adapter: UsageAdapter,
	auth: unknown,
	signal: AbortSignal,
	timeoutMs: number,
) => Promise<UsageReport>;

type LimitError = {
	id: string;
	modelProvider?: string;
	modelId?: string;
};

type PendingResume = LimitError & {
	ctx: ExtensionContext;
	sessionId: string;
	generation: number;
	timer?: ReturnType<typeof setTimeout>;
	notified: boolean;
	queryWarningShown: boolean;
};

type State = {
	pending: PendingResume | undefined;
	generation: number;
};

function asRecord(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === "object" ? (value as Record<string, unknown>) : undefined;
}

function textContent(value: unknown): string {
	if (typeof value === "string") return value;
	if (!Array.isArray(value)) return "";
	return value
		.filter((part) => asRecord(part)?.type === "text")
		.map((part) => {
			const text = asRecord(part)?.text;
			return typeof text === "string" ? text : "";
		})
		.join("");
}

function isCodexLimitErrorEntry(entry: unknown): entry is {
	id: string;
	message: Record<string, unknown>;
} {
	const record = asRecord(entry);
	const message = asRecord(record?.message);
	if (typeof record?.id !== "string" || message?.role !== "assistant") return false;

	const provider = message.provider;
	if (typeof provider === "string" && provider !== CODEX_PROVIDER) return false;

	return [
		typeof message.errorMessage === "string" ? message.errorMessage : "",
		textContent(message.content),
	].some((value) => value === LIMIT_MESSAGE);
}

function latestLimitError(ctx: ExtensionContext): LimitError | undefined {
	const leaf = ctx.sessionManager.getBranch().at(-1);
	if (!isCodexLimitErrorEntry(leaf)) return undefined;

	const modelProvider = leaf.message.provider;
	const modelId = leaf.message.model;
	return {
		id: leaf.id,
		...(typeof modelProvider === "string" ? { modelProvider } : {}),
		...(typeof modelId === "string" ? { modelId } : {}),
	};
}

function isSameLimitError(pending: PendingResume, error: LimitError): boolean {
	return pending.id === error.id;
}

function isStaleContextError(error: unknown): boolean {
	return error instanceof Error && error.message.includes("stale after session replacement or reload");
}

function notify(ctx: ExtensionContext, message: string, type: "info" | "warning" | "error"): void {
	try {
		ctx.ui.notify(message, type);
	} catch {
		// A session replacement can invalidate the UI while a timer is completing.
	}
}

function setStatus(ctx: ExtensionContext, value: string | undefined): void {
	try {
		ctx.ui.setStatus(STATUS_KEY, value);
	} catch {
		// A stale context is harmless; the next session_start will install the status.
	}
}

function formatDelay(delayMs: number): string {
	const totalMinutes = Math.max(1, Math.ceil(delayMs / 60_000));
	const hours = Math.floor(totalMinutes / 60);
	const minutes = totalMinutes % 60;
	if (hours > 0) return `${hours}h ${minutes}m`;
	return `${minutes}m`;
}

function fiveHourBucket(report: UsageReport): UsageBucket | undefined {
	const fiveHour = report.buckets.find(
		(bucket) =>
			bucket.unit === "percent" &&
			bucket.windowMinutes !== undefined &&
			Math.abs(bucket.windowMinutes - FIVE_HOUR_MINUTES) <= 10,
	);
	if (fiveHour) return fiveHour;

	return report.buckets.find(
		(bucket) => bucket.unit === "percent" && bucket.id === "codex:primary",
	);
}

function bucketIsExhausted(bucket: UsageBucket): boolean {
	if (bucket.remaining === undefined && bucket.used === undefined) return true;
	if (bucket.remaining !== undefined) return bucket.remaining <= 0;
	return bucket.used !== undefined && bucket.used >= 100;
}

function resetDelay(bucket: UsageBucket): number {
	if (bucket.resetsAt !== undefined && Number.isFinite(bucket.resetsAt)) {
		const untilReset = bucket.resetsAt * 1_000 - Date.now();
		return untilReset > 0 ? untilReset + RESET_GRACE_MS : POLL_INTERVAL_MS;
	}
	return POLL_INTERVAL_MS;
}

function clearPending(pending: PendingResume | undefined): void {
	if (!pending) return;
	if (pending.timer !== undefined) clearTimeout(pending.timer);
	setStatus(pending.ctx, undefined);
}

function cancelPending(state: State): void {
	state.generation += 1;
	const pending = state.pending;
	state.pending = undefined;
	clearPending(pending);
}

function schedule(pending: PendingResume, delayMs: number, check: (pending: PendingResume) => void): void {
	if (pending.timer !== undefined) clearTimeout(pending.timer);
	const delay = Math.min(Math.max(0, delayMs), MAX_TIMER_DELAY_MS);
	pending.timer = setTimeout(() => {
		pending.timer = undefined;
		check(pending);
	}, delay);
}

async function queryCodexUsage(ctx: ExtensionContext): Promise<UsageReport> {
	const adapter = getUsageAdapter(CODEX_PROVIDER);
	if (!adapter) throw new Error("The Codex usage adapter is unavailable");

	const auth = await getUsageAuth(ctx, adapter);
	if (!auth) throw new Error("OpenAI Codex credentials are unavailable");

	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), USAGE_QUERY_TIMEOUT_MS);
	try {
		return await getUsageReport(adapter, auth, controller.signal, USAGE_QUERY_TIMEOUT_MS);
	} finally {
		clearTimeout(timeout);
	}
}

function waitingStatus(bucket: UsageBucket | undefined): string {
	if (!bucket) return "Codex 5h limit active · checking again soon";
	const delay = resetDelay(bucket);
	return `Codex 5h limit active · checking again in ${formatDelay(delay)}`;
}

function retryAfterResumeFailure(
	pending: PendingResume,
	state: State,
	pi: ExtensionAPI,
	error: unknown,
): void {
	if (state.generation !== pending.generation || state.pending !== undefined) return;
	if (isStaleContextError(error)) return;

	state.pending = pending;
	notify(
		pending.ctx,
		`Automatic Codex continuation failed; will retry: ${error instanceof Error ? error.message : String(error)}`,
		"warning",
	);
	setStatus(pending.ctx, "Codex automatic continuation will be retried");
	schedule(pending, RESUME_RETRY_INTERVAL_MS, (next) => void checkPending(next, state, pi));
}

function resumeWithMessage(pending: PendingResume, state: State, pi: ExtensionAPI): void {
	if (state.pending !== pending) return;
	const ctx = pending.ctx;

	try {
		if (ctx.sessionManager.getSessionId() !== pending.sessionId) {
			cancelPending(state);
			return;
		}
		if (!ctx.isIdle() || ctx.hasPendingMessages()) {
			setStatus(ctx, "Codex 5h limit active · waiting for Pi to become idle");
			schedule(pending, RESUME_RETRY_INTERVAL_MS, (next) => void checkPending(next, state, pi));
			return;
		}

		const error = latestLimitError(ctx);
		if (!error || !isSameLimitError(pending, error)) {
			cancelPending(state);
			return;
		}

		state.pending = undefined;
		clearPending(pending);
		notify(ctx, "Codex 5h limit refreshed; resuming the session.", "info");

		// This intentionally adds the literal user message requested by the user.
		// No private AgentSession API or Pi runtime patch is required.
		pi.sendUserMessage("Continue");
	} catch (error) {
		retryAfterResumeFailure(pending, state, pi, error);
	}
}

async function checkPending(pending: PendingResume, state: State, pi: ExtensionAPI): Promise<void> {
	if (state.pending !== pending) return;
	const ctx = pending.ctx;

	try {
		if (ctx.sessionManager.getSessionId() !== pending.sessionId) {
			cancelPending(state);
			return;
		}

		if (!ctx.isIdle() || ctx.hasPendingMessages()) {
			setStatus(ctx, "Codex 5h limit active · waiting for Pi to become idle");
			schedule(pending, RESUME_RETRY_INTERVAL_MS, (next) => void checkPending(next, state, pi));
			return;
		}

		const error = latestLimitError(ctx);
		if (!error || !isSameLimitError(pending, error)) {
			cancelPending(state);
			return;
		}

		let report: UsageReport;
		try {
			report = await queryCodexUsage(ctx);
		} catch (error) {
			if (state.pending !== pending) return;
			if (isStaleContextError(error)) {
				cancelPending(state);
				return;
			}
			if (!pending.queryWarningShown) {
				pending.queryWarningShown = true;
				notify(
					ctx,
					`Unable to read Codex usage; will keep checking: ${error instanceof Error ? error.message : String(error)}`,
					"warning",
				);
			}
			setStatus(ctx, "Codex 5h limit active · usage check unavailable");
			schedule(pending, POLL_INTERVAL_MS, (next) => void checkPending(next, state, pi));
			return;
		}
		if (state.pending !== pending) return;

		const bucket = fiveHourBucket(report);
		if (!bucket) {
			setStatus(ctx, "Codex 5h limit active · 5h usage unavailable");
			schedule(pending, POLL_INTERVAL_MS, (next) => void checkPending(next, state, pi));
			return;
		}
		if (bucketIsExhausted(bucket)) {
			setStatus(ctx, waitingStatus(bucket));
			schedule(pending, resetDelay(bucket), (next) => void checkPending(next, state, pi));
			return;
		}

		resumeWithMessage(pending, state, pi);
	} catch (error) {
		if (state.pending !== pending) return;
		if (isStaleContextError(error)) {
			cancelPending(state);
			return;
		}
		setStatus(ctx, "Codex automatic continuation will be retried");
		schedule(pending, POLL_INTERVAL_MS, (next) => void checkPending(next, state, pi));
	}
}

function arm(ctx: ExtensionContext, state: State, pi: ExtensionAPI): void {
	const sessionId = ctx.sessionManager.getSessionId();
	if (state.pending && state.pending.sessionId !== sessionId) cancelPending(state);

	const error = latestLimitError(ctx);
	if (!error) {
		if (state.pending) cancelPending(state);
		return;
	}

	if (
		(error.modelProvider !== undefined && error.modelProvider !== CODEX_PROVIDER) ||
		(ctx.model?.provider !== undefined && ctx.model.provider !== CODEX_PROVIDER)
	) {
		if (state.pending) cancelPending(state);
		return;
	}

	const current = state.pending;
	if (current && current.sessionId === sessionId && isSameLimitError(current, error)) {
		current.ctx = ctx;
		return;
	}
	if (current) cancelPending(state);

	const pending: PendingResume = {
		...error,
		ctx,
		sessionId,
		generation: state.generation,
		notified: false,
		queryWarningShown: false,
	};
	state.pending = pending;
	if (!pending.notified) {
		pending.notified = true;
		notify(ctx, "Codex 5h limit reached; waiting for the limit to refresh.", "warning");
	}
	setStatus(ctx, "Codex 5h limit active · checking usage");
	schedule(pending, 0, (next) => void checkPending(next, state, pi));
}

export default function codexLimitAutocontinue(pi: ExtensionAPI): void {
	const state: State = { pending: undefined, generation: 0 };

	pi.on("session_start", async (_event, ctx) => {
		arm(ctx, state, pi);
	});

	pi.on("agent_settled", async (_event, ctx) => {
		arm(ctx, state, pi);
	});

	pi.on("session_tree", async (_event, ctx) => {
		arm(ctx, state, pi);
	});

	pi.on("model_select", async () => {
		// A deliberate model change cancels an automatic resume. Do not re-arm
		// from a historical error on the newly selected model.
		cancelPending(state);
	});

	pi.on("input", async () => {
		cancelPending(state);
	});

	pi.on("agent_start", async () => {
		cancelPending(state);
	});

	pi.on("session_shutdown", async () => {
		cancelPending(state);
	});
}
