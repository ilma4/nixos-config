import { writeFile } from "node:fs/promises";

export interface Assignment {
  lineNumber: number; indent: string; name: string; value: string; trailing: string;
}

export function assignments(text: string): Assignment[] {
  const found: Assignment[] = [];
  for (const [lineNumber, line] of text.split("\n").entries()) {
    const assignment = parseAssignment(lineNumber, line);
    if (assignment) found.push(assignment);
  }
  return found;
}

export function selectAssignment(name: string, allAssignments: readonly Assignment[]): Assignment {
  const matches = allAssignments.filter((assignment): boolean => assignment.name === name);
  if (matches.length === 1) return matches[0]!;
  throw new Error(`Error: Version variable ${JSON.stringify(name)} ${matches.length ? "is not unique" : "was not found"}`);
}

export async function writeAssignment(
  apply: boolean, path: string, text: string, assignment: Assignment, newValue: string,
): Promise<void> {
  validateValue(newValue);
  if (assignment.value === newValue) {
    console.log(`${path}: ${assignment.name} is already ${newValue}`);
    return;
  }
  const line = `${assignment.indent}${assignment.name} = "${newValue}";${assignment.trailing}`;
  if (apply) await writeFile(path, replaceLine(text, assignment.lineNumber, line));
  console.log(`${apply ? "Updated" : "Would update"} ${path}: ${assignment.name} ${assignment.value} -> ${newValue}`);
}

function parseAssignment(lineNumber: number, line: string): Assignment | undefined {
  const match = line.match(/^(\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*"([^"]*)";(.*)$/);
  if (!match) return undefined;
  const [, indent, name, value, trailing] = match;
  return { lineNumber, indent: indent!, name: name!, value: value!, trailing: trailing! };
}

function validateValue(value: string): void {
  if (!value) throw new Error("Error: Version must not be empty");
  if (/["\\\n\r]/.test(value)) throw new Error("Error: Version contains characters this script will not quote");
}

function replaceLine(text: string, lineNumber: number, replacement: string): string {
  const lines = text.split("\n");
  lines[lineNumber] = replacement;
  return lines.join("\n");
}
