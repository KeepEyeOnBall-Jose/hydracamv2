const { chromium } = require("/Users/jose/src/work/media-timeline/node_modules/playwright/index.js");
const fs = require('fs');
const url = "http://localhost:5173/events/hydracam-wearable-live-1782145676315358/videos/92691e90-2640-4955-b8ed-be59146da47d";
const resultPath = "/Users/jose/src/work/hydracamv2/logs/verification-runs/browser-proof-smoke-2/browser-proof.json";
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const failures = [];
  const consoleIssues = [];
  page.on('response', response => {
    if (response.status() >= 400) failures.push(`${response.status()} ${response.url()}`);
  });
  page.on('console', message => {
    if (['warning', 'error'].includes(message.type())) {
      consoleIssues.push(`${message.type()}: ${message.text()}`);
    }
  });
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.getByTestId('wearable-replay-overlay').waitFor({ timeout: 15000 });
  const overlayText = (await page.getByTestId('wearable-replay-overlay').innerText())
    .replace(/\s+/g, ' ')
    .trim();
  await page.waitForTimeout(1000);
  fs.writeFileSync(resultPath, JSON.stringify({
    url,
    overlayText,
    failures,
    consoleIssues,
  }, null, 2));
  await browser.close();
})().catch(async error => {
  fs.writeFileSync(resultPath, JSON.stringify({
    url,
    error: String(error && error.stack ? error.stack : error),
  }, null, 2));
  process.exit(1);
});
