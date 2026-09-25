// Capture frames of a replay page (generate_replay) with Playwright.
//
//   npm install playwright            # once; plus: npx playwright install chromium
//   node scripts/capture/capture_replay.js docs/replay/iberia.html frames/ 100
//   python3 scripts/capture/make_gif.py frames/ docs/assets/replay_iberia.gif
//
// Offline: set PLOTLY_JS=/path/to/plotly.min.js and TOPOJSON_DIR=/path/to/sane-topojson/dist
// to serve plotly.js and the map outlines from local files instead of the CDN.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path = require('path');
const fs = require('fs');

const [file, outDir, n = '100'] = process.argv.slice(2);
const nframes = Math.max(2, +n);

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1000, height: 490 } });
  page.on('pageerror', e => console.error('page error:', e.message));
  if (process.env.PLOTLY_JS || process.env.TOPOJSON_DIR) {
    await page.route('**/*', route => {
      const u = route.request().url();
      if (process.env.PLOTLY_JS && u.includes('plotly')  && u.endsWith('.js'))
        return route.fulfill({ path: process.env.PLOTLY_JS, contentType: 'application/javascript' });
      const m = u.match(/cdn\.plot\.ly\/.*?([a-z-]+_\d+m\.json)/);
      if (process.env.TOPOJSON_DIR && m)
        return route.fulfill({ path: path.join(process.env.TOPOJSON_DIR, m[1]), contentType: 'application/json' });
      return route.continue();
    });
  }
  await page.goto('file://' + path.resolve(file) + '?capture');
  await page.waitForFunction(() => window.replayReady === true, null, { timeout: 30000 });
  await page.waitForSelector('.geolayer path', { timeout: 30000 });
  await page.waitForTimeout(500);
  const tmax = await page.evaluate(() => D.tmax);
  for (let i = 0; i < nframes; i++) {
    await page.evaluate(ts => window.renderAt(ts), tmax * i / (nframes - 1));
    await page.screenshot({ path: path.join(outDir, `f_${String(i).padStart(4, '0')}.png`) });
  }
  await browser.close();
  console.log(`captured ${nframes} frames to ${outDir}`);
})();
