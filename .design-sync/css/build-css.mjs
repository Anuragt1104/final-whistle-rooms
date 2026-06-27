// Compiles the app's Tailwind v4 design language into one static stylesheet
// for design-sync previews. Scans the real components AND the authored
// previews so every utility class either uses is materialized. Deterministic;
// re-run before the final build after authoring previews.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import postcss from 'postcss';
import tailwind from '@tailwindcss/postcss';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '..', '..');

// Reuse the app's real globals (tokens, @layer components, animations,
// body background) verbatim — only swap auto-detection for explicit @source
// globs so the scan is reproducible regardless of cwd.
const globals = readFileSync(resolve(repo, 'app', 'globals.css'), 'utf8');
const body = globals.replace(/@import\s+["']tailwindcss["'];?/, '').trimStart();

const input = [
  '@import "tailwindcss" source(none);',
  '@source "../../components/**/*.{ts,tsx,js,jsx}";',
  '@source "../previews/**/*.{ts,tsx,js,jsx}";',
  '',
  body,
].join('\n');

const inputPath = resolve(here, 'input.css');
writeFileSync(inputPath, input);

const result = await postcss([tailwind()]).process(input, { from: inputPath });
const outPath = resolve(here, 'compiled.css');
writeFileSync(outPath, result.css);
console.error(`compiled.css: ${(result.css.length / 1024).toFixed(1)} KB`);
