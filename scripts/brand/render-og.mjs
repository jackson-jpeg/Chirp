// Renders website/img/og.png (1200×630), the link-preview card, in the
// "Sky classic" look: the icon's sky, clouds and birds, with the headline set
// in the repo's own Barlow Condensed / IBM Plex Mono (fonts/).
//
//   node scripts/brand/render-og.mjs      # from the repo root

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const globalRoot = execFileSync('npm', ['root', '-g']).toString().trim();
const { chromium } = createRequire(import.meta.url)(path.join(globalRoot, 'playwright'));

const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const font = (f) => fs.readFileSync(path.join(repo, 'fonts', f)).toString('base64');
const icon = fs.readFileSync(path.join(repo, 'icon.svg'), 'utf8');
const bird = icon.slice(icon.indexOf('<g id="bird">'), icon.indexOf('<g id="cloud">'));

const cloud = (x, y, w) =>
  `<svg viewBox="-62 -118 274 192" style="position:absolute;left:${x}px;top:${y}px;width:${w}px">` +
  `<g fill="#cfe8f7" transform="translate(0 12)"><circle r="60"/><circle cx="72" cy="-34" r="82"/><circle cx="150" r="60"/><rect width="150" height="60"/></g>` +
  `<g fill="#fff"><circle r="60"/><circle cx="72" cy="-34" r="82"/><circle cx="150" r="60"/><rect width="150" height="60"/></g></svg>`;

const html = `<!doctype html><html><head><style>
@font-face { font-family: Barlow; src: url(data:font/ttf;base64,${font('BarlowCondensed-Bold.ttf')}); font-weight: 700; }
@font-face { font-family: Plex; src: url(data:font/ttf;base64,${font('IBMPlexMono-Medium.ttf')}); font-weight: 500; }
body { margin: 0; }
.card { position: relative; width: 1200px; height: 630px; overflow: hidden;
  background: linear-gradient(180deg, #4aacea 0%, #9fd9f7 100%); font-family: Barlow; color: #1f2d52; }
.copy { position: absolute; left: 72px; top: 92px; z-index: 2; }
.eyebrow { font-family: Plex; font-size: 20px; letter-spacing: .3em; text-transform: uppercase; margin: 0 0 22px; }
h1 { margin: 0; font-size: 116px; line-height: .88; text-transform: uppercase; }
h1 .hl { background: linear-gradient(transparent 12%, #ffc93a 12%, #ffc93a 90%, transparent 90%); padding: 0 .06em; }
.sub { font-family: Plex; font-size: 22px; letter-spacing: .04em; margin-top: 30px; max-width: 520px; line-height: 1.45; }
.birds { position: absolute; right: 24px; bottom: 22px; width: 540px; overflow: visible; }
</style></head><body><div class="card">
${cloud(720, 40, 170)}${cloud(1010, 150, 130)}${cloud(24, 540, 120)}
<div class="copy">
  <p class="eyebrow">ChirpChirps · for iPhone</p>
  <h1>No signal?<br><span class="hl">Still works.</span></h1>
  <p class="sub">A walkie-talkie mesh between nearby iPhones. No towers, no internet, no accounts.</p>
</div>
<svg class="birds" viewBox="100 330 824 406">
  <defs>${bird}</defs>
  <g transform="translate(0 50)">
    <path d="M-2000 626 L436 626 L452 606 L468 652 L484 580 L500 676 L512 560 L524 676 L540 580 L556 652 L572 606 L588 626 L1400 626" stroke="#1f2d52" stroke-width="10" stroke-linejoin="round" stroke-linecap="round" fill="none"/>
    <g transform="translate(318 464) scale(0.9)"><use href="#bird"/><path d="M134 -48 L190 -38 L136 -24 Z" fill="#ff7a2e"/><path d="M136 -16 L180 -4 L132 0 Z" fill="#ff7a2e"/></g>
    <g transform="translate(706 464) scale(-0.9 0.9)"><use href="#bird"/><path d="M134 -44 L186 -26 L134 -8 Z" fill="#ff7a2e"/></g>
  </g>
</svg>
</div></body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 630 } });
await page.setContent(html);
await page.evaluate(() => document.fonts.ready);
const out = path.join(repo, 'website/img/og.png');
await page.screenshot({ path: out });
await browser.close();
execFileSync('python3', ['-c', `from PIL import Image; import sys; Image.open(sys.argv[1]).convert('RGB').save(sys.argv[1], optimize=True)`, out]);
console.log('og.png → website/img/og.png');
