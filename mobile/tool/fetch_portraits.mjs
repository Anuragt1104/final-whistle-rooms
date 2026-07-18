import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const selections = {
  mbappe: ['Kylian Mbappé', 'File:Kylian Mbappe France v Senegal 16 June 2026-354 (cropped).jpg'],
  messi: ['Lionel Messi', 'File:Lionel-Messi-Argentina-2022-FIFA-World-Cup (cropped).jpg'],
  bellingham: ['Jude Bellingham', 'File:Jude Bellingham England v Ghana 23 June 2026-061 (cropped).jpg'],
  vinicius: ['Vinícius Jr', 'File:Vinicius Junior Brazil V Morocco 13 June 2026-94 (cropped).jpg'],
  yamal: ['Lamine Yamal', 'File:Lamine Yamal in 2025 (cropped2).jpg'],
  saka: ['Bukayo Saka', 'File:Bukayo Saka.jpg'],
  musiala: ['Jamal Musiala', 'File:Jamal Musiala 2022 (cropped).jpg'],
  wirtz: ['Florian Wirtz', 'File:Florian Wirtz Ecuador v Germany 25 June 2026-006.jpg'],
  pedri: ['Pedri', 'File:Pedri (cropped).jpg'],
  rodri: ['Rodri', 'File:Yokohama F. Marinos - Manchester City (3-5) - 53075487835 (Rodri) (cropped).jpg'],
  valverde: ['Fede Valverde', 'File:Federico Valverde 2021 (cropped).jpg'],
  alvarez: ['Julián Álvarez', 'File:Julián Álvarez (footballer) 2023 2.jpg'],
  lautaro: ['Lautaro Martínez', 'File:Lautaro Martínez (cropped).jpg'],
  raphinha: ['Raphinha', 'File:Raphinha.jpg'],
  hakimi: ['Achraf Hakimi', 'File:Achraf Hakimi 2024.jpg'],
  saliba: ['William Saliba', 'File:Lens - Nice (23-01-2021) 44 (cropped).jpg'],
  vandijk: ['Virgil van Dijk', 'File:20160604 AUT NED 8876 (cropped).jpg'],
  donnarumma: ['Gianluigi Donnarumma', 'File:Norway Italy - June 2025 B 33 - Gianluigi Donnarumma (close-up).jpg'],
  courtois: ['Thibaut Courtois', 'File:Courtois 2018 (cropped).jpg'],
  kane: ['Harry Kane', 'File:Harry Kane 2023 (cropped).jpg'],
  son: ['Son Heung-min', 'File:Son Heung-min - 2022 (52552243725) (cropped).jpg'],
  osimen: ['Victor Osimhen', 'File:Victor Osimhen (LOSC) (cropped).jpg'],
  guler: ['Arda Güler', 'File:Derbide Fenerbahçe Yedek Oyuncu Arda Güler (2021-22 Süper Lig - Cropped).jpg'],
  frimpong: ['Jeremie Frimpong', 'File:Jeremie Frimpong 04012026 (3) (cropped).jpg'],
};

const accepted = /^(CC0|CC BY(?:-SA)?(?: [234]\.0)?(?: [a-z]+)?|Public domain|Attribution)$/i;
const params = new URLSearchParams({
  action: 'query',
  titles: Object.values(selections).map(([, title]) => title).join('|'),
  prop: 'imageinfo',
  iiprop: 'url|extmetadata',
  iiurlwidth: '720',
  format: 'json',
  origin: '*',
});

const response = await fetch(`https://commons.wikimedia.org/w/api.php?${params}`, {
  headers: { 'User-Agent': 'FinalWhistleHackathon/1.0 portrait-attribution' },
});
if (!response.ok) throw new Error(`Commons API ${response.status}`);
const json = await response.json();
const pages = new Map(Object.values(json.query?.pages ?? {}).map((page) => [page.title, page]));
const outDir = resolve('assets/cards/portraits');
mkdirSync(outDir, { recursive: true });

const clean = (value = '') => value
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ')
  .replace(/&amp;/g, '&')
  .replace(/&#0*39;|&apos;/g, "'")
  .replace(/&quot;/g, '"')
  .replace(/\s+/g, ' ')
  .trim();

const manifest = {};
const sleep = (milliseconds) => new Promise((resolveSleep) => setTimeout(resolveSleep, milliseconds));
async function downloadWithRetry(url, title) {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    await sleep(650 + attempt * 1200);
    const result = await fetch(url, {
      headers: { 'User-Agent': 'FinalWhistleHackathon/1.0 portrait-bundler' },
    });
    if (result.ok) return result;
    if (result.status !== 429) throw new Error(`Download ${result.status}: ${title}`);
  }
  throw new Error(`Download rate limit persisted: ${title}`);
}

for (const [id, [name, title]] of Object.entries(selections)) {
  const page = pages.get(title);
  const info = page?.imageinfo?.[0];
  const meta = info?.extmetadata ?? {};
  const license = clean(meta.LicenseShortName?.value);
  if (!info?.thumburl) throw new Error(`Missing image for ${id}: ${title}`);
  if (!accepted.test(license)) throw new Error(`Rejected license ${license} for ${id}`);
  const output = resolve(outDir, `${id}.webp`);
  if (!existsSync(output)) {
    const downloaded = await downloadWithRetry(info.thumburl, title);
    const input = resolve(`/tmp/final-whistle-${id}.jpg`);
    writeFileSync(input, Buffer.from(await downloaded.arrayBuffer()));
    execFileSync('cwebp', [
      '-quiet', '-mt', '-q', '82', input, '-o', output,
    ], { stdio: 'ignore' });
  }
  manifest[id] = {
    name,
    assetPath: `assets/cards/portraits/${id}.webp`,
    sourcePage: info.descriptionurl,
    author: clean(meta.Artist?.value || meta.Credit?.value || 'Wikimedia Commons contributor'),
    license,
    licenseUrl: clean(meta.LicenseUrl?.value),
    discoveryUrl: `https://commons.wikimedia.org/w/index.php?search=${encodeURIComponent(name + ' football')}&title=Special:MediaSearch&type=image`,
    modified: 'Resized and converted to WebP; displayed with runtime crop and color effects.',
  };
}

writeFileSync(resolve(outDir, 'attribution.json'), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Bundled ${Object.keys(manifest).length} attributed portraits in ${outDir}`);
