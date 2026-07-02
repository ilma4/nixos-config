import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const IJPROXY_MCP_TOOL_NAME = /mcp__ijproxy__([0-9A-Za-z_]+)/g;

function fixIjproxyMcpToolNames(text: string): string {
	return text.replace(IJPROXY_MCP_TOOL_NAME, "ijproxy_$1");
}

export default function ijproxyMcpAgentsMdFix(pi: ExtensionAPI) {
	pi.on("before_agent_start", (event) => {
		const contextFiles = event.systemPromptOptions.contextFiles ?? [];
		let systemPrompt = event.systemPrompt;
		let changed = false;

		for (const contextFile of contextFiles) {
			const fixedContent = fixIjproxyMcpToolNames(contextFile.content);
			if (fixedContent === contextFile.content) continue;

			const oldBlock = `<project_instructions path="${contextFile.path}">\n${contextFile.content}\n</project_instructions>`;
			const newBlock = `<project_instructions path="${contextFile.path}">\n${fixedContent}\n</project_instructions>`;

			if (systemPrompt.includes(oldBlock)) {
				systemPrompt = systemPrompt.replace(oldBlock, newBlock);
			} else {
				// If another extension has already reshaped the prompt, still make the
				// requested context-file name fix in the prompt the model will receive.
				systemPrompt = fixIjproxyMcpToolNames(systemPrompt);
			}

			changed = true;
		}

		if (changed) {
			return { systemPrompt };
		}
	});
}
