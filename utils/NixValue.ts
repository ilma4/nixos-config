import { writeFile } from "node:fs/promises";

export interface Assignment {
  lineNumber: number; indent: string; name: string; value: string; trailing: string;
}

export function assignments(text: string): Assignment[] {
  return text.split("\n").flatMap((line, lineNumber) => {
    const match = line.match(/^(\s*)([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*"([^"]*)";(.*)$/);
    if (!match) return [];
    const [, indent, name, value, trailing] = match;
    return [{ lineNumber, indent: indent!, name: name!, value: value!, trailing: trailing! }];
  });
}

export function selectAssignment(name: string, allAssignments: readonly Assignment[]): Assignment {
  const matches = allAssignments.filter((assignment) => assignment.name === name);
  if (matches.length === 1) return matches[0]!;
  throw new Error(`Error: Version variable ${JSON.stringify(name)} ${matches.length ? "is not unique" : "was not found"}`);
}

export async function writeAssignment(
  apply: boolean, path: string, text: string, assignment: Assignment, newValue: string,
): Promise<void> {
  if (!newValue) throw new Error("Error: Version must not be empty");
  if (/["\\\n\r]/.test(newValue)) throw new Error("Error: Version contains characters this script will not quote");
  if (assignment.value === newValue) {
    console.log(`${path}: ${assignment.name} is already ${newValue}`);
    return;
  }
  const line = `${assignment.indent}${assignment.name} = "${newValue}";${assignment.trailing}`;
  if (apply) {
    const lines = text.split("\n");
    lines[assignment.lineNumber] = line;
    await writeFile(path, lines.join("\n"));
  }
  console.log(`${apply ? "Updated" : "Would update"} ${path}: ${assignment.name} ${assignment.value} -> ${newValue}`);
}
