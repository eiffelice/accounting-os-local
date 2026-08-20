import { access, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const manifest = JSON.parse(
  await readFile(path.join(root, 'third_party', 'omise-banks-logo', 'banks.json'), 'utf8')
);
const expected = Object.keys(manifest.th).sort();
const assetDir = path.join(root, 'apps', 'web', 'public', 'bank-logos');
const actual = (await readdir(assetDir)).filter((file) => file.endsWith('.svg')).map((file) => file.slice(0, -4)).sort();
const migration = await readFile(
  path.join(root, 'db', 'migrations', '009_bank_directory_and_logos.sql'),
  'utf8'
);

if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  throw new Error(`bank logo asset mismatch: expected ${expected.length}, found ${actual.length}`);
}

const unsafeSvg = /<!DOCTYPE\b|<script\b|\bon(?:load|error)\s*=|javascript:|<foreignObject\b|<image\b|(?:xlink:)?href\s*=|url\s*\(\s*['"]?\s*(?:https?:|data:|\/\/)/i;
for (const slug of expected) {
  const svg = await readFile(path.join(assetDir, `${slug}.svg`), 'utf8');
  if (!/<svg\b/i.test(svg) || unsafeSvg.test(svg)) throw new Error(`unsafe or invalid SVG content in ${slug}.svg`);
}

const seedRows = new Map(
  [...migration.matchAll(/\('([a-z0-9]+)','([0-9]{3})','[^']+','(#[0-9a-fA-F]{6})','[0-9a-f]{40}'\)/g)]
    .map((match) => [match[1], { sourceCode: match[2], color: match[3].toLowerCase() }])
);
if (seedRows.size !== expected.length) throw new Error('bank directory migration does not match manifest size');
for (const slug of expected) {
  const seeded = seedRows.get(slug);
  const source = manifest.th[slug];
  if (!seeded || seeded.sourceCode !== source.code || seeded.color !== source.color.toLowerCase()) {
    throw new Error(`bank directory migration mismatch for ${slug}`);
  }
}

await access(path.join(root, 'third_party', 'omise-banks-logo', 'LICENSE'));
console.log(`PASS: ${actual.length} local bank logos and migration rows match the licensed manifest and contain no active content`);
