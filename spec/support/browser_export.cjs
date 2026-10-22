// Run after browser_fixtures.rb. Playwright is a development-only dependency.
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');

(async () => {
  const directory = path.resolve(process.argv[2]);
  const fixtures = JSON.parse(await fs.readFile(path.join(directory, 'fixtures.json'), 'utf8'));
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({ offline: true, acceptDownloads: true });
    for (const fixture of fixtures) {
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
      const remoteRequests = [];
      page.on('request', request => { if (/^https?:/.test(request.url())) remoteRequests.push(request.url()); });
      await page.addInitScript(() => {
        let embed;
        window.chartResults = [];
        Object.defineProperty(window, 'vegaEmbed', {
          configurable: true,
          get() { return embed; },
          set(original) {
            embed = Object.assign(function (...args) {
              const result = original(...args);
              window.chartResults.push(result);
              return result;
            }, original);
          }
        });
      });
      await page.goto(pathToFileURL(path.join(directory, fixture.name + '.html')).href);
      await page.waitForFunction(() => window.chartResults.length === 1);
      const before = await page.evaluate(async () => {
        window.chartView = (await window.chartResults[0]).view;
        return window.chartView.toSVG();
      });
      assert(before.includes('avg: 35.00'), fixture.name + ': main-axis stacked statistics');
      assert(before.includes(fixture.stacked_secondary ? 'avg: 212.50' : 'avg: 106.25'), fixture.name + ': second-axis statistics');
      assert(before.includes('測定結果'));

      await page.locator('input[type="checkbox"]').nth(1).uncheck();
      await page.waitForFunction(async () => (await window.chartView.toSVG()).includes('avg: 15.00'));
      const dimensions = await page.evaluate(async () => {
        const canvas = await window.chartView.toCanvas(1);
        return { width: canvas.width, height: canvas.height };
      });
      await page.locator('summary').click();
      assert.equal(await page.locator('.vega-actions a').count(), 2);
      for (const format of ['png', 'svg']) {
        const downloadEvent = page.waitForEvent('download');
        await page.getByText('Save as ' + format.toUpperCase(), { exact: true }).click();
        const download = await downloadEvent;
        assert(download.suggestedFilename().endsWith('.' + format));
        const bytes = await fs.readFile(await download.path());
        if (format === 'png') {
          assert.equal(bytes.subarray(1, 4).toString(), 'PNG');
          assert.equal(bytes.readUInt32BE(16), dimensions.width * 2);
          assert.equal(bytes.readUInt32BE(20), dimensions.height * 2);
        } else {
          assert(bytes.toString().includes('<svg'));
          assert(bytes.toString().includes('avg: 15.00'));
        }
      }
      assert.deepEqual(errors, [], fixture.name + ': browser errors');
      assert.deepEqual(remoteRequests, [], fixture.name + ': offline network requests');
      console.log(fixture.name + ': offline rendering, statistics, controls, PNG/SVG downloads passed');
      await page.close();
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
