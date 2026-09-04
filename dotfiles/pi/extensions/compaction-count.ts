import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "compaction-count";

function updateStatus(ctx: ExtensionContext): void {
	const compactionCount = ctx.sessionManager.getBranch().filter((entry) => entry.type === "compaction").length;
	if (compactionCount === 0) {
		ctx.ui.setStatus(STATUS_KEY, undefined);
		return;
	}

	ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("dim", `compactions: ${compactionCount}`));
}

export default function compactionCountExtension(pi: ExtensionAPI): void {
	pi.on("session_start", async (_event, ctx) => {
		updateStatus(ctx);
	});

	pi.on("session_compact", async (_event, ctx) => {
		updateStatus(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		updateStatus(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		ctx.ui.setStatus(STATUS_KEY, undefined);
	});
}
