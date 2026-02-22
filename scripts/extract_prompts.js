#!/usr/bin/env node
// Extracts workspace system prompts from an AnythingLLM SQLite DB
// Usage: node extract_prompts.js <path-to-db> <output-file>

const { execSync } = require('child_process');
const fs = require('fs');

const dbPath = process.argv[2];
const outPath = process.argv[3];

if (!dbPath || !outPath) {
  console.error('Usage: node extract_prompts.js <db-path> <output-path>');
  process.exit(1);
}

// Use sqlite3 CLI with JSON mode via Docker
const raw = execSync(
  `docker run --rm -v "${dbPath}:/data/source.db:ro" alpine/sqlite:latest /data/source.db ".mode json" "SELECT id, name, openAiPrompt FROM workspaces ORDER BY id;"`,
  { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 }
);

const workspaces = JSON.parse(raw.trim());

const lines = [
  '# Workspace System Prompts',
  '',
  `Extracted from AnythingLLM database on ${new Date().toISOString()}.`,
  '',
];

for (const ws of workspaces) {
  lines.push('---', '');
  lines.push(`## ${ws.name || '(unnamed)'} (id: ${ws.id})`, '');
  if (ws.openAiPrompt && ws.openAiPrompt.trim()) {
    lines.push(ws.openAiPrompt.trim(), '');
  } else {
    lines.push('_No system prompt set._', '');
  }
}

const content = lines.join('\n');
fs.writeFileSync(outPath, content, 'utf8');
console.log(`Written ${workspaces.length} workspace(s) to: ${outPath}`);
workspaces.forEach(ws => {
  const hasPrompt = !!(ws.openAiPrompt && ws.openAiPrompt.trim());
  console.log(`  [${ws.id}] ${ws.name}: ${hasPrompt ? 'has prompt' : 'NO PROMPT'}`);
});
