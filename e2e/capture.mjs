/**
 * capture.mjs
 *
 * Logs in as each given user in a real Edge instance, screenshots the shell and
 * reports which navigation items and top-bar buttons that role can see. This is
 * how permission differences get verified visually rather than assumed.
 *
 * Uses puppeteer-core pointed at the installed Edge, so nothing hundreds of
 * megabytes gets downloaded.
 *
 * Usage:
 *   node capture.mjs --users=xiaoran.ma,siyuan.li --out=<dir> [--base=http://localhost:8080]
 *                    [--password=Qms@2026] [--edge=<path to msedge.exe>] [--pages=/#/complaints]
 */
import fs from 'node:fs'
import path from 'node:path'
import puppeteer from 'puppeteer-core'

const argv = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, '').split('=')
    return [key, rest.join('=')]
  })
)

const base = argv.base ?? 'http://localhost:8080'
const outDir = argv.out ?? '.'
const password = argv.password ?? 'Qms@2026'
const users = (argv.users ?? '').split(',').filter(Boolean)
const pages = (argv.pages ?? '').split(',').filter(Boolean)
const edge = argv.edge

if (!edge) {
  console.error('missing --edge=<path to msedge.exe>')
  process.exit(2)
}
if (users.length === 0) {
  console.error('missing --users=a,b,c')
  process.exit(2)
}

fs.mkdirSync(outDir, { recursive: true })

const browser = await puppeteer.launch({
  executablePath: edge,
  headless: true,
  args: ['--no-first-run', '--no-default-browser-check', '--disable-gpu', '--hide-scrollbars']
})

const report = []

for (const username of users) {
  // A fresh context per user: the access token lives in localStorage, so
  // reusing one context would leak the previous session into the next login.
  const context = browser.createBrowserContext
    ? await browser.createBrowserContext()
    : await browser.createIncognitoBrowserContext()
  const page = await context.newPage()
  await page.setViewport({ width: 1680, height: 1050 })

  const entry = { username, ok: false, error: null, user: null, nav: [], iconButtons: 0, shots: [] }

  try {
    await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
    await page.evaluate(() => localStorage.clear())
    await page.reload({ waitUntil: 'networkidle2' })

    await page.waitForSelector('input[type="text"]', { timeout: 20000 })
    await page.type('input[type="text"]', username)
    await page.type('input[type="password"]', password)
    await page.click('button[type="submit"]')

    await page.waitForFunction(
      () => !!document.querySelector('.app-sidebar .nav-item'),
      { timeout: 25000 }
    )
    await new Promise((r) => setTimeout(r, 900))

    entry.nav = await page.$$eval('.app-sidebar .nav-item-text', (els) =>
      els.map((e) => e.textContent.trim())
    )
    entry.user = await page
      .$eval('.topbar-right .fs-12', (e) => e.textContent.trim())
      .catch(() => null)
    entry.iconButtons = await page.$$eval('.topbar-right .icon-btn', (els) => els.length)

    const shellShot = path.join(outDir, `shell-${username}.png`)
    await page.screenshot({ path: shellShot })
    entry.shots.push(shellShot)

    for (const route of pages) {
      const slug = route.replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'root'
      const target = route.startsWith('/#') ? `${base}${route}` : `${base}/#${route}`
      const targetShot = path.join(outDir, `${username}__${slug}.png`)
      try {
        await page.goto(target, { waitUntil: 'networkidle2', timeout: 40000 })
        await new Promise((r) => setTimeout(r, 900))
        const heading = await page.$eval('h1', (e) => e.textContent.trim()).catch(() => '')
        await page.screenshot({ path: targetShot })
        entry.shots.push(targetShot)
        if (!entry.headings) entry.headings = {}
        entry.headings[route] = heading
      } catch (err) {
        if (!entry.headings) entry.headings = {}
        entry.headings[route] = `ERROR ${err.message}`
      }
    }

    entry.ok = true
  } catch (err) {
    entry.error = err.message
  } finally {
    await context.close()
  }

  report.push(entry)
}

await browser.close()

const jsonPath = path.join(outDir, 'ui_capture.json')
fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2))
console.log(JSON.stringify(report, null, 2))
