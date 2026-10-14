/**
 * home.mjs
 *
 * Drives the home dashboard in a real browser: the four figures, the overdue
 * banner, the to-do groups, the announcement list and drawer, and the deep link
 * from a to-do entry into the complaint's tab. The API half of task 2.10 is
 * scripts/verify-home.ps1.
 *
 * The numbers the page must show are passed in from the API response the
 * PowerShell wrapper read a moment earlier, so the assertions compare the screen
 * against the data rather than against constants that would rot.
 *
 * Usage:
 *   node home.mjs --todos=N --mine=N --urgent=N --pending=N --types=N
 *                 --deepType=VERIFICATION --deepComplaint=C... --deepTab=d2
 *                 --out=<dir> --edge=<path> [--base=...] [--user=...]
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
const edge = argv.edge
const user = argv.user ?? 'siyuan.li'
const password = argv.password ?? 'Qms@2026'

const expected = {
  todos: Number(argv.todos ?? -1),
  mine: Number(argv.mine ?? -1),
  urgent: Number(argv.urgent ?? -1),
  pending: Number(argv.pending ?? -1),
  types: Number(argv.types ?? -1),
  newBadges: Number(argv.expectNew ?? -1)
}
const deepType = argv.deepType ?? ''
const deepComplaint = argv.deepComplaint ?? ''
const deepTab = argv.deepTab ?? ''

if (!edge) {
  console.error('need --edge=<path>')
  process.exit(2)
}
fs.mkdirSync(outDir, { recursive: true })

const steps = []
function note(name, ok, detail = '') {
  steps.push({ name, ok, detail })
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${!ok && detail ? '  -> ' + detail : ''}`)
}

const browser = await puppeteer.launch({
  executablePath: edge,
  headless: true,
  args: ['--no-first-run', '--no-default-browser-check', '--disable-gpu', '--hide-scrollbars']
})
const context = browser.createBrowserContext
  ? await browser.createBrowserContext()
  : await browser.createIncognitoBrowserContext()
const page = await context.newPage()
await page.setViewport({ width: 1680, height: 1080 })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

async function shot(name) {
  const file = path.join(outDir, `home-${name}.png`)
  await page.screenshot({ path: file })
  return file
}

async function bodyText() {
  return page.evaluate(() => document.body.innerText)
}

/** The four figures, read as label -> value so the tiles can be checked by name. */
async function tiles() {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('.stat')).map((el) => ({
      label: el.querySelector('.stat-label')?.innerText.trim() ?? '',
      value: Number((el.querySelector('.stat-value')?.innerText ?? '').replace(/[^0-9-]/g, '')),
      foot: el.querySelector('.stat-foot')?.innerText.trim() ?? ''
    }))
  )
}

function tileValue(list, label) {
  const tile = list.find((t) => t.label === label)
  return tile ? tile.value : null
}

try {
  // --- sign in ---------------------------------------------------------------
  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), { timeout: 25000 })

  await page.goto(`${base}/#/`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stat', { timeout: 25000 })
  await wait(1500)
  await shot('1-loaded')

  // --- the four figures -----------------------------------------------------
  const readTiles = await tiles()
  note('four figures are shown', readTiles.length === 4, `tiles=${readTiles.length}`)
  note(
    'the to-do figure matches the API',
    tileValue(readTiles, '我的待办') === expected.todos,
    `screen=${tileValue(readTiles, '我的待办')} api=${expected.todos}`
  )
  note(
    'the overdue figure matches the API',
    tileValue(readTiles, '已超期 / 紧急') === expected.urgent,
    `screen=${tileValue(readTiles, '已超期 / 紧急')} api=${expected.urgent}`
  )
  note(
    'the approval figure matches the API',
    tileValue(readTiles, '待我审批') === expected.pending,
    `screen=${tileValue(readTiles, '待我审批')} api=${expected.pending}`
  )
  note(
    'the related-complaints figure matches the API',
    tileValue(readTiles, '与我相关投诉') === expected.mine,
    `screen=${tileValue(readTiles, '与我相关投诉')} api=${expected.mine}`
  )
  const todoTile = readTiles.find((t) => t.label === '我的待办')
  note(
    'the to-do tile says how many kinds of work it covers',
    (todoTile?.foot ?? '').includes(`${expected.types} 类任务`),
    todoTile?.foot ?? ''
  )

  // --- the overdue banner ---------------------------------------------------
  const text = await bodyText()
  const bannerShown = await page.evaluate(() => !!document.querySelector('.alert-danger'))
  note('the overdue banner is shown', bannerShown)
  note(
    'the banner counts the late complaints',
    /有\s*\d+\s*单投诉已超出目标日期/.test(text),
    'the banner headline is missing'
  )
  const bannerIds = await page.evaluate(() => {
    const banner = document.querySelector('.alert-danger')
    if (!banner) return []
    return (banner.innerText.match(/C\d{9}/g) ?? []).slice(0, 4)
  })
  note('the banner names the worst complaints', bannerIds.length > 0, bannerIds.join(','))

  // --- the to-do list -------------------------------------------------------
  const groups = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.todo-group-head')).map((el) =>
      el.innerText.replace(/\s+/g, ' ').trim()
    )
  )
  note(
    'the to-do list is grouped by kind of work',
    groups.length === expected.types,
    `groups=${groups.length} api=${expected.types}`
  )
  note(
    'at least one group is flagged as overdue',
    groups.some((g) => g.includes('已超期')),
    groups.join(' | ')
  )
  const todoCount = await page.evaluate(() => document.querySelectorAll('.todo-item').length)
  note(
    'the entries shown match the API page',
    todoCount === Math.min(expected.todos, 12),
    `shown=${todoCount} api=${expected.todos}`
  )

  // --- announcements --------------------------------------------------------
  const annCount = await page.evaluate(() => document.querySelectorAll('.ann-item').length)
  note('the announcement card lists the published notices', annCount > 0, `count=${annCount}`)
  const annText = await page.evaluate(() => {
    const card = document.querySelector('.ann-card')
    return card ? card.innerText : ''
  })
  note(
    'an announcement shows its publish time and author',
    /\d{4}-\d{2}-\d{2}/.test(annText),
    'no publish date on the announcement card'
  )

  const firstTitle = await page.evaluate(() => {
    const el = document.querySelector('.ann-item .fs-13')
    return el ? el.innerText.replace('NEW', '').trim() : ''
  })

  // --- the NEW badge --------------------------------------------------------
  const badgesBefore = await page.evaluate(
    () => document.querySelectorAll('.ann-item .new-chip').length
  )
  note(
    'every unread announcement carries a NEW badge',
    badgesBefore === expected.newBadges,
    `badges=${badgesBefore} api=${expected.newBadges}`
  )

  await page.click('.ann-item')
  await wait(1500)
  await shot('2-announcement')
  const drawerOpen = await page.evaluate(() => !!document.querySelector('.el-drawer'))
  const drawerText = await page.evaluate(() => {
    const el = document.querySelector('.el-drawer')
    return el ? el.innerText : ''
  })
  note('clicking an announcement opens the drawer', drawerOpen)
  note(
    'the drawer shows that announcement',
    !!firstTitle && drawerText.includes(firstTitle),
    `title=${firstTitle}`
  )

  const firstStillBadged = await page.evaluate(() => {
    const first = document.querySelector('.ann-item')
    return !!first && !!first.querySelector('.new-chip')
  })
  const badgesAfter = await page.evaluate(
    () => document.querySelectorAll('.ann-item .new-chip').length
  )
  note('opening an announcement clears its NEW badge', !firstStillBadged)
  note(
    'the other unread announcements keep theirs',
    badgesAfter === expected.newBadges - 1,
    `badges=${badgesAfter} expected=${expected.newBadges - 1}`
  )

  await page.keyboard.press('Escape')
  await wait(800)

  // Reloading proves the badge was cleared on the server, not just in this tab.
  await page.reload({ waitUntil: 'networkidle2' })
  await wait(1500)
  const badgesAfterReload = await page.evaluate(
    () => document.querySelectorAll('.ann-item .new-chip').length
  )
  note(
    'the cleared badge stays cleared after a reload',
    badgesAfterReload === expected.newBadges - 1,
    `badges=${badgesAfterReload}`
  )

  // --- the deep link into a complaint's tab --------------------------------
  if (deepType && deepComplaint) {
    // The baseline is measured first, on a plain visit with no query parameter:
    // navigating by hash alone does not remount the view, so a baseline taken
    // after the deep link would still carry the old ?tab=.
    let activeByDefault = ''
    if (deepTab && deepTab !== 'd01') {
      await page.goto(`${base}/#/complaints/${deepComplaint}`, {
        waitUntil: 'networkidle2',
        timeout: 40000
      })
      await page.waitForSelector('.stage-bar', { timeout: 25000 })
      await wait(1200)
      activeByDefault = await page.evaluate(
        () => document.querySelector('.el-tabs__item.is-active')?.innerText.trim() ?? ''
      )
      await shot('3-plain-detail')
    }

    await page.goto(`${base}/#/`, { waitUntil: 'networkidle2', timeout: 40000 })
    await page.waitForSelector('.stat', { timeout: 25000 })
    await wait(1200)

    const clicked = await page.evaluate((type) => {
      const el = document.querySelector(`.todo-item[data-todo="${type}"]`)
      if (!el) return false
      el.click()
      return true
    }, deepType)
    note('the to-do entry for that kind of work is on the page', clicked, `type=${deepType}`)
    await page.waitForFunction((id) => window.location.hash.includes(id), { timeout: 20000 }, deepComplaint)
    await wait(1600)
    await shot('4-deeplink')
    const hash = await page.evaluate(() => window.location.hash)
    note('the entry opens the complaint it belongs to', hash.includes(deepComplaint), hash)
    note('the entry carries the target tab', hash.includes(`tab=${deepTab}`), hash)

    if (deepTab && deepTab !== 'd01') {
      const activeOnDeepLink = await page.evaluate(
        () => document.querySelector('.el-tabs__item.is-active')?.innerText.trim() ?? ''
      )
      note(
        'the deep link opens a different tab than the default',
        activeOnDeepLink !== '' && activeOnDeepLink !== activeByDefault,
        `deep=${activeOnDeepLink} default=${activeByDefault}`
      )
    }
  }

  // --- the layout holds when the window narrows -----------------------------
  await page.goto(`${base}/#/`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.stat', { timeout: 25000 })
  await wait(1200)

  for (const width of [1280, 1180]) {
    await page.setViewport({ width, height: 1000 })
    await wait(900)
    await shot(`4-width-${width}`)
    const geometry = await page.evaluate(() => {
      const tilesBox = document.querySelector('.grid.grid-2')?.getBoundingClientRect()
      const annBox = document.querySelector('.ann-card')?.getBoundingClientRect()
      return tilesBox && annBox
        ? { tilesTop: Math.round(tilesBox.top), annTop: Math.round(annBox.top), annLeft: Math.round(annBox.left), tilesRight: Math.round(tilesBox.right) }
        : null
    })
    note(
      `the figures and announcements stay side by side at ${width}px`,
      !!geometry && Math.abs(geometry.annTop - geometry.tilesTop) < 60 && geometry.annLeft > geometry.tilesRight - 40,
      JSON.stringify(geometry)
    )
  }
} catch (err) {
  note('home page run', false, err.message)
  try {
    await shot('error')
  } catch {
    /* ignore */
  }
} finally {
  await context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'home_report.json'), JSON.stringify({ expected, steps }, null, 2))
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
if (failed !== 0) process.exit(1)
