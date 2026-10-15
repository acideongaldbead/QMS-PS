/**
 * open-app.mjs
 *
 * Opens the running QMS app in a visible Edge window, already signed in as a
 * given user, and leaves the window open for a human to look at. A convenience,
 * not part of any test run.
 *
 *   node open-app.mjs --user=ying.zhou --password=Qms@2026 --edge="<msedge.exe>"
 *                     [--base=http://localhost:8080] [--hash=#/kb]
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import puppeteer from 'puppeteer-core'

const argv = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, '').split('=')
    return [key, rest.join('=')]
  })
)

const base = argv.base ?? 'http://localhost:8080'
const edge = argv.edge
const user = argv.user ?? 'ying.zhou'
const password = argv.password ?? 'Qms@2026'
const hash = argv.hash ?? '#/'

if (!edge) {
  console.error('need --edge=<path to msedge.exe>')
  process.exit(2)
}

// A throwaway profile keeps the real browser profile untouched and gives the
// session somewhere to persist, so the window stays signed in after we detach.
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'qms-open-'))

const browser = await puppeteer.launch({
  executablePath: edge,
  headless: false,
  userDataDir: profile,
  args: ['--no-first-run', '--no-default-browser-check']
})

const page = await browser.newPage()
await page.setViewport({ width: 1440, height: 900 })
await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 60000 })
await page.waitForSelector('input[type="text"]', { timeout: 30000 })
await page.type('input[type="text"]', user)
await page.type('input[type="password"]', password)
await page.click('button[type="submit"]')
await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), {
  timeout: 30000
})
await page.goto(`${base}/${hash}`, { waitUntil: 'networkidle2', timeout: 60000 })
await page.bringToFront()

console.log(`signed in as ${user}; the Edge window stays open`)
browser.disconnect()
process.exit(0)
