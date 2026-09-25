// Renders the brand SVGs (icon.svg, icon-night.svg) to every PNG the app and
// the website ship. The SVGs are the source of truth; never hand-edit a PNG.
//
//   node scripts/brand/render-icons.mjs            # from the repo root
//
// Needs Playwright's Chromium (preinstalled on the VPS and in cloud sessions;
// `npm root -g` must contain playwright). App Store icons must have no alpha
// channel, so every opaque PNG is flattened to RGB via Pillow afterwards
// (`python3 -m pip install pillow` once).

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const globalRoot = execFileSync('npm', ['root', '-g']).toString().trim();
const { chromium } = createRequire(import.meta.url)(path.join(globalRoot, 'playwright'));

const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const svg = (name) => fs.readFileSync(path.join(repo, name), 'utf8');
const day = svg('icon.svg');
const night = svg('icon-night.svg');

const appIconDir = path.join(repo, 'Chirp/Resources/Assets.xcassets/AppIcon.appiconset');
const siteDir = path.join(repo, 'website');

// [svg, pixel size, output path, corner radius as a fraction of size (0 = square)]
const jobs = [
  [day, 1024, path.join(appIconDir, 'icon_1024.png'), 0],
  [night, 1024, path.join(appIconDir, 'icon_1024_dark.png'), 0],
  [day, 180, path.join(siteDir, 'apple-touch-icon.png'), 0],
  [day, 32, path.join(siteDir, 'favicon-32x32.png'), 0.225],
  [day, 16, path.join(siteDir, 'favicon-16x16.png'), 0.225],
  [day, 48, path.join(siteDir, 'favicon-48.png'), 0.225],
  [day, 512, path.join(siteDir, 'img/icon-512.png'), 0.225],
];

const browser = await chromium.launch();
const page = await browser.newPage();
const flatten = [];
for (const [source, size, out, radius] of jobs) {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  await page.setViewportSize({ width: size, height: size });
  const src = `data:image/svg+xml;base64,${Buffer.from(source).toString('base64')}`;
  await page.setContent(
    `<html><body style="margin:0;background:transparent">` +
    `<img src="${src}" width="${size}" height="${size}" style="display:block;border-radius:${radius * size}px"></body></html>`
  );
  await page.waitForFunction(() => document.images[0].complete);
  await page.screenshot({ path: out, omitBackground: radius > 0 });
  if (radius === 0) flatten.push(out);
  console.log(`${size}px → ${path.relative(repo, out)}`);
}
await browser.close();

execFileSync('python3', ['-c', `
import sys
from PIL import Image
for p in sys.argv[1:]:
    Image.open(p).convert('RGB').save(p, optimize=True)
`, ...flatten]);

// favicon.ico: 16 + 32 + 48, from the rounded renders.
execFileSync('python3', ['-c', `
from PIL import Image
import sys
d = sys.argv[1]
img = Image.open(d + '/favicon-48.png').convert('RGBA')
img.save(d + '/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
`, siteDir]);
fs.rmSync(path.join(siteDir, 'favicon-48.png'));
console.log('favicon.ico → website/favicon.ico');
