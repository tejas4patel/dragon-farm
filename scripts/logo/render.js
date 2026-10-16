// Render HTML pages to transparent PNGs with headless Edge.
// Usage: node render.js page.html out.png width height [scale] [page2.html out2.png w h scale ...]
const { chromium } = require('playwright-core');
const { spawn } = require('child_process');
const os = require('os');
const fs = require('fs');
const path = require('path');

(async () => {
  const args = process.argv.slice(2);
  const jobs = [];
  for (let i = 0; i < args.length; i += 5) {
    jobs.push({ html: args[i], out: args[i + 1], w: +args[i + 2], h: +args[i + 3], scale: +(args[i + 4] || 1) });
  }
  const PORT = 9341;
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'dragonfarm-render-'));
  const edge = spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', [
    '--headless=new', '--remote-debugging-port=' + PORT, '--user-data-dir=' + profile,
    '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--hide-scrollbars',
  ], { stdio: 'ignore' });
  for (let i = 0; i < 50; i++) {
    try { const r = await fetch('http://127.0.0.1:' + PORT + '/json/version'); if (r.ok) break; } catch (e) {}
    await new Promise((r) => setTimeout(r, 300));
  }
  const browser = await chromium.connectOverCDP('http://127.0.0.1:' + PORT);
  try {
    for (const j of jobs) {
      const context = await browser.newContext({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: j.scale });
      const page = await context.newPage();
      await page.goto('file:///' + path.resolve(j.html).replace(/\\/g, '/'));
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(300);
      await page.screenshot({ path: j.out, omitBackground: true, clip: { x: 0, y: 0, width: j.w, height: j.h } });
      await context.close();
      console.log('wrote', j.out);
    }
  } finally {
    await browser.close().catch(() => {});
    edge.kill();
  }
})().catch((e) => { console.error(e); process.exit(1); });
