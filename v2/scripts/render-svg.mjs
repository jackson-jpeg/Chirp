// Render an SVG to an opaque PNG at an exact pixel size with headless Chromium.
// Chromium is used (not ImageMagick) because the design's SVG relies on CSS
// custom properties inside <use>, which only a browser engine resolves.
//
//   node v2/scripts/render-svg.mjs <in.svg> <out.png> <size>
//
// Playwright is not a dependency of this repo; set PLAYWRIGHT_DIR to any
// installed copy (on the VPS: /root/PlotSlop/node_modules/playwright).
// Run it through `heavy`.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const [, , input, output, sizeArg] = process.argv;
if (!input || !output || !sizeArg) {
  console.error('usage: render-svg.mjs <in.svg> <out.png> <size>');
  process.exit(2);
}
const size = Number(sizeArg);
const dir = process.env.PLAYWRIGHT_DIR ?? '/root/PlotSlop/node_modules/playwright';
const { chromium } = createRequire(import.meta.url)(dir);

const svg = readFileSync(resolve(input), 'utf8');
const html = `<!doctype html><html><head><style>html,body{margin:0;background:#fff}svg{display:block;width:${size}px;height:${size}px}</style></head><body>${svg}</body></html>`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
  await page.setContent(html);
  await page.screenshot({ path: resolve(output), omitBackground: false, clip: { x: 0, y: 0, width: size, height: size } });
} finally {
  await browser.close();
}
console.log(`wrote ${output} (${size}x${size})`);
