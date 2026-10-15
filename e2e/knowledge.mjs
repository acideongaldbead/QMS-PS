/**
 * knowledge.mjs
 *
 * Drives the knowledge centre (requirement 3.11) in a real browser: the document
 * list grouped by category, the category filter with its counts, the keyword
 * search, the administrator's create / upload / delete flow, and the fact that a
 * reader without knowledge:manage sees no maintenance controls at all.
 *
 * The API half is scripts/verify-knowledge.ps1; scripts/ui-knowledge.ps1 seeds
 * the documents this script asserts on and cleans them up afterwards.
 *
 * Usage:
 *   node knowledge.mjs --docA=<id> --codeA=... --catA=... --docB=<id> --codeB=...
 *                      --catProcess=<label> --catTraining=<label> --total=<n>
 *                      --keyword=... --png=<path>
 *                      --out=<dir> --edge=<path> [--base=...] [--user=...]
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
const password = argv.password ?? 'Qms@2026'
const adminUser = argv.user ?? 'ying.zhou'
const engineerUser = argv.engineer ?? 'siyuan.li'

const docA = Number(argv.docA ?? -1)
const codeA = argv.codeA ?? ''
const catA = argv.catA ?? ''
const docB = Number(argv.docB ?? -1)
const docxDoc = Number(argv.docxDoc ?? -1)
const xlsxDoc = Number(argv.xlsxDoc ?? -1)
const pptxDoc = Number(argv.pptxDoc ?? -1)
const catProcess = argv.catProcess ?? ''
const expectedTotal = Number(argv.total ?? -1)
const keyword = argv.keyword ?? codeA
const png = argv.png ?? ''
/** The browser uploads the file under its own name, not one we choose. */
const pngName = path.basename(png)

if (!edge || docA < 0 || !png) {
  console.error('need --edge=<path> --docA=<id> --png=<path>')
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
const wait = (ms) => new Promise((r) => setTimeout(r, ms))

/**
 * A fresh browser context per user: the access token lives in localStorage, so
 * sharing one context between the administrator and the engineer would sign the
 * first one out mid-run.
 */
async function signIn(user) {
  const context = browser.createBrowserContext
    ? await browser.createBrowserContext()
    : await browser.createIncognitoBrowserContext()
  const page = await context.newPage()
  await page.setViewport({ width: 1680, height: 1080 })
  const downloads = []
  page.on('response', (res) => {
    if (/\/api\/attachments\/\d+\/download/.test(res.url())) downloads.push(res.url())
  })

  await page.goto(`${base}/#/login`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.evaluate(() => localStorage.clear())
  await page.reload({ waitUntil: 'networkidle2' })
  await page.waitForSelector('input[type="text"]', { timeout: 20000 })
  await page.type('input[type="text"]', user)
  await page.type('input[type="password"]', password)
  await page.click('button[type="submit"]')
  await page.waitForFunction(() => !!document.querySelector('.app-sidebar .nav-item'), {
    timeout: 25000
  })
  await page.goto(`${base}/#/kb`, { waitUntil: 'networkidle2', timeout: 40000 })
  await page.waitForSelector('.kb-row', { timeout: 25000 })
  await wait(1200)
  return { context, page, downloads }
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(outDir, `kb-${name}.png`) })
}

/** The number shown next to a category in the sidebar, or null. */
async function sideCount(page, code) {
  return page.evaluate((c) => {
    const el = document.querySelector(`[data-cat="${c}"] .count-pill`)
    return el ? Number(el.innerText.trim()) : null
  }, code)
}

async function rowIds(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('.kb-row')).map((el) => Number(el.dataset.doc))
  )
}

async function rowAction(page, docId, act) {
  return page.evaluate(
    (id, a) => {
      const row = document.querySelector(`.kb-row[data-doc="${id}"]`)
      const btn = row?.querySelector(`[data-act="${a}"]`)
      if (!btn) return 'missing'
      return btn.disabled ? 'disabled' : 'enabled'
    },
    docId,
    act
  )
}

/** Clicks a row action through the real mouse, so Element's own handlers run. */
async function clickRowAction(page, docId, act) {
  const box = await page.evaluate(
    (id, a) => {
      const row = document.querySelector(`.kb-row[data-doc="${id}"]`)
      const btn = row?.querySelector(`[data-act="${a}"]`)
      if (!btn) return null
      const r = btn.getBoundingClientRect()
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
    },
    docId,
    act
  )
  if (!box) return false
  await page.mouse.click(box.x, box.y)
  return true
}

async function search(page, text) {
  await page.click('[data-kb-search] input', { clickCount: 3 })
  await page.keyboard.press('Backspace')
  if (text) await page.type('[data-kb-search] input', text)
  await page.keyboard.press('Enter')
  await wait(1200)
}

async function pickCategory(page, code) {
  await page.evaluate((c) => document.querySelector(`[data-cat="${c}"]`)?.click(), code)
  await wait(1200)
}

const created = []
let admin
let engineer

try {
  // =========================================================================
  // Administrator: sees the library and maintains it
  // =========================================================================
  admin = await signIn(adminUser)
  const page = admin.page

  await shot(page, '1-admin-list')

  const chrome = await page.evaluate(() => document.body.innerText)
  note('the page is titled in Chinese', chrome.includes('知识中心'), 'title missing')
  note('the document list is headed 全部文档', chrome.includes('全部文档'), 'card title missing')
  note('the category card is headed 文档分类', chrome.includes('文档分类'), 'sidebar title missing')

  // --- the sidebar ----------------------------------------------------------
  const catCodes = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-cat]')).map((el) => el.dataset.cat)
  )
  note(
    'the sidebar lists 全部 plus the four dictionary categories',
    catCodes.length === 5 && catCodes[0] === '',
    `codes=${catCodes.join(',')}`
  )
  const allCount = await sideCount(page, '')
  note(
    'the 全部 count matches the API summary',
    allCount === expectedTotal,
    `screen=${allCount} api=${expectedTotal}`
  )
  const groupHeads = await page.evaluate(() =>
    Array.from(document.querySelectorAll('.kb-group-head')).map((el) =>
      el.innerText.replace(/\s+/g, ' ').trim()
    )
  )
  note(
    'the document groups are headed by the Chinese category names',
    groupHeads.some((g) => g.includes(catProcess)),
    groupHeads.join(' | ')
  )
  const emptyCats = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-cat]'))
      .filter((el) => el.dataset.cat !== '')
      .filter((el) => Number(el.querySelector('.count-pill')?.innerText.trim() ?? '-1') === 0)
      .map((el) => el.dataset.cat)
  )
  note(
    'a dictionary category holding no document still appears, with a zero',
    emptyCats.length >= 1,
    `zero-count categories=${emptyCats.join(',')}`
  )

  // --- a seeded row ---------------------------------------------------------
  const seededRow = await page.evaluate((id) => {
    const row = document.querySelector(`.kb-row[data-doc="${id}"]`)
    return row ? row.innerText.replace(/\s+/g, ' ').trim() : ''
  }, docA)
  note('the seeded document is listed', seededRow.length > 0, `row=${docA}`)
  note('the row shows the document number', seededRow.includes(codeA), seededRow)
  note('the row shows the version badge', seededRow.includes('V1.0'), seededRow)

  // --- preview availability follows the file type ---------------------------
  note(
    'a document holding a PDF or image offers a preview',
    (await rowAction(page, docA, 'preview')) === 'enabled',
    'expected the preview button to be enabled'
  )
  note(
    'a document with no file has its preview disabled',
    docB >= 0 && (await rowAction(page, docB, 'preview')) === 'disabled',
    'expected the preview button to be disabled'
  )

  // --- Office documents preview in-page -------------------------------------
  // Each format gets a real file and a real assertion: "claims to support" is not
  // the same as "verified" (docs/retrospective.md 3.7-8). The bytes are parsed in
  // the browser, so these assertions also prove the renderers actually load.
  async function previewText() {
    return page.evaluate(() => {
      const el = document.querySelector('[data-doc-preview]')
      return el ? el.innerText.replace(/\s+/g, ' ').trim() : ''
    })
  }
  async function closePreview() {
    await page.evaluate(() => document.querySelector('.el-dialog__headerbtn')?.click())
    await wait(900)
  }

  // Word: the checked-in XTE-0071 template renders its own body text.
  note('the Word document offers a preview', await clickRowAction(page, docxDoc, 'preview'), `row=${docxDoc}`)
  await page.waitForSelector('[data-doc-preview]', { timeout: 20000 })
  let docxRendered = true
  try {
    await page.waitForFunction(
      () => !!document.querySelector('[data-doc-preview] .docx-wrapper'),
      { timeout: 30000 }
    )
  } catch {
    docxRendered = false
  }
  {
    const text = await previewText()
    note(
      'the Word document renders its body',
      docxRendered && text.replace(/\s+/g, '').includes('Read-across'),
      text.slice(0, 200)
    )
  }
  await wait(700)
  await shot(page, '10-preview-docx')
  await closePreview()

  // Excel: a real POI workbook; its first header cell is 流程ID.
  note('the Excel document offers a preview', await clickRowAction(page, xlsxDoc, 'preview'), `row=${xlsxDoc}`)
  await page.waitForSelector('[data-doc-preview]', { timeout: 20000 })
  let xlsxRendered = true
  try {
    await page.waitForFunction(
      () => !!document.querySelector('[data-doc-preview] [data-doc-sheet-table]'),
      { timeout: 30000 }
    )
  } catch {
    xlsxRendered = false
  }
  {
    const text = await previewText()
    const rows = await page.evaluate(
      () => document.querySelectorAll('[data-doc-preview] [data-doc-sheet-table] tr').length
    )
    note('the Excel document renders a table', xlsxRendered && rows >= 1, `rows=${rows}`)
    note('the Excel table shows the ledger header', text.includes('流程ID'), text.slice(0, 200))
  }
  await wait(700)
  await shot(page, '11-preview-xlsx')
  await closePreview()

  // PowerPoint: the generated fixture's slide carries a known title run.
  note('the PowerPoint document offers a preview', await clickRowAction(page, pptxDoc, 'preview'), `row=${pptxDoc}`)
  await page.waitForSelector('[data-doc-preview]', { timeout: 20000 })
  let pptxRendered = true
  try {
    await page.waitForFunction(
      () => (document.querySelector('[data-doc-preview]')?.innerText ?? '').includes('PPTX PREVIEW'),
      { timeout: 30000 }
    )
  } catch {
    pptxRendered = false
  }
  {
    const text = await previewText()
    note('the PowerPoint deck renders its slide text', pptxRendered && text.includes('PPTX PREVIEW'), text.slice(0, 200))
  }
  await wait(700)
  await shot(page, '12-preview-pptx')
  await closePreview()

  // --- category filter ------------------------------------------------------
  await pickCategory(page, catA)
  const filteredByCat = await rowIds(page)
  note(
    'choosing a category keeps the document that belongs to it',
    filteredByCat.includes(docA),
    `rows=${filteredByCat.join(',')}`
  )
  note(
    'choosing a category drops the others',
    docB < 0 || !filteredByCat.includes(docB),
    `rows=${filteredByCat.join(',')}`
  )
  await shot(page, '2-category-filter')

  await pickCategory(page, '')
  await wait(600)

  // --- keyword search -------------------------------------------------------
  await search(page, keyword)
  const searched = await rowIds(page)
  note(
    'searching by document number keeps only that document',
    searched.length === 1 && searched[0] === docA,
    `rows=${searched.join(',')}`
  )
  await shot(page, '3-search')

  await search(page, 'ZZZ_NO_SUCH_DOC')
  const none = await rowIds(page)
  note('a keyword that matches nothing shows the empty state', none.length === 0, `rows=${none.length}`)
  const emptyShown = await page.evaluate(() => !!document.querySelector('.empty-title'))
  note('the empty state is rendered', emptyShown)
  await shot(page, '4-empty')

  await search(page, '')
  await wait(600)

  // --- create ---------------------------------------------------------------
  const newTitle = `UI Acceptance ${Date.now()}`
  const newCode = `UIKB-${Date.now()}`
  await page.click('[data-kb-new]')
  await page.waitForSelector('.el-dialog', { timeout: 15000 })
  await wait(700)
  await page.type('[data-kb-field-title] input', newTitle)
  await page.type('[data-kb-field-code] input', newCode)
  await page.type('[data-kb-field-version] input', 'V9.9')
  await page.click('[data-kb-save]')
  await page.waitForFunction(
    (code) => document.body.innerText.includes(code),
    { timeout: 20000 },
    newCode
  )
  await wait(1000)

  const createdRow = await page.evaluate((code) => {
    const rows = Array.from(document.querySelectorAll('.kb-row'))
    const row = rows.find((el) => el.innerText.includes(code))
    return row ? Number(row.dataset.doc) : -1
  }, newCode)
  note('creating a document adds it to the list', createdRow > 0, `id=${createdRow}`)
  note(
    'the new document shows the version that was typed',
    await page.evaluate(
      (id) => {
        const row = document.querySelector(`.kb-row[data-doc="${id}"]`)
        return !!row && row.innerText.includes('V9.9')
      },
      createdRow
    ),
    'version badge missing'
  )
  if (createdRow > 0) created.push(createdRow)
  await shot(page, '5-created')

  // --- upload the document file through the edit dialog ---------------------
  await clickRowAction(page, createdRow, 'edit')
  await page.waitForSelector('[data-kb-files]', { timeout: 15000 })
  await wait(900)

  const fileInput = await page.$('[data-kb-files] input[type="file"]')
  if (fileInput) {
    await fileInput.uploadFile(png)
    await wait(2500)
  }
  const panelText = await page.evaluate(() => {
    const el = document.querySelector('[data-kb-files]')
    return el ? el.innerText.replace(/\s+/g, ' ').trim() : ''
  })
  note('the edit dialog offers the document-file panel', !!fileInput, 'no file input found')
  note(
    'the uploaded file is listed in the panel',
    panelText.includes(pngName),
    panelText.slice(0, 300)
  )
  await shot(page, '6-edit-dialog')

  await page.click('.el-dialog__footer .el-button:not(.el-button--primary)')
  await wait(1500)
  await shot(page, '6-uploaded')

  const afterUpload = await page.evaluate(
    (id) => {
      const row = document.querySelector(`.kb-row[data-doc="${id}"]`)
      return row ? row.innerText.replace(/\s+/g, ' ').trim() : ''
    },
    createdRow
  )
  note('the list row now shows the file size', /(\d+(\.\d+)?\s*(B|KB|MB))/.test(afterUpload), afterUpload)

  // --- download goes through the authenticated endpoint ---------------------
  const before = admin.downloads.length
  await clickRowAction(page, createdRow, 'download')
  await wait(2000)
  note(
    'downloading fetches the file through the attachment endpoint',
    admin.downloads.length > before,
    `requests=${admin.downloads.length}`
  )

  // --- delete ---------------------------------------------------------------
  await clickRowAction(page, createdRow, 'delete')
  await page.waitForSelector('.el-message-box', { timeout: 15000 })
  await wait(600)
  await page.click('.el-message-box__btns .el-button--primary')
  await wait(2000)
  const gone = await page.evaluate(
    (id) => !document.querySelector(`.kb-row[data-doc="${id}"]`),
    createdRow
  )
  note('deleting a document removes it from the list', gone, `id=${createdRow}`)
  await shot(page, '7-deleted')

  // --- the layout holds at the two widths ----------------------------------
  for (const width of [1280, 1180]) {
    await page.setViewport({ width, height: 1000 })
    await wait(900)
    await shot(page, `8-width-${width}`)
    const geometry = await page.evaluate(() => {
      const main = document.querySelector('section > .card')?.getBoundingClientRect()
      const side = document.querySelector('aside > .card')?.getBoundingClientRect()
      return main && side
        ? {
            mainTop: Math.round(main.top),
            mainRight: Math.round(main.right),
            sideTop: Math.round(side.top),
            sideLeft: Math.round(side.left),
            sideWidth: Math.round(side.width)
          }
        : null
    })
    note(
      `the filter sidebar stays beside the list at ${width}px`,
      !!geometry && Math.abs(geometry.sideTop - geometry.mainTop) < 60 && geometry.sideLeft > geometry.mainRight - 60,
      JSON.stringify(geometry)
    )
  }

  await admin.context.close()

  // =========================================================================
  // Engineer: reads the library, maintains nothing
  // =========================================================================
  engineer = await signIn(engineerUser)
  const eng = engineer.page
  await shot(eng, '9-engineer-list')

  const engText = await eng.evaluate(() => document.body.innerText)
  note('the engineer can open the knowledge centre', engText.includes('知识中心'), 'page missing')
  note('the engineer sees the document list', (await rowIds(eng)).length > 0, 'no rows')
  note(
    'the engineer is not offered the create button',
    (await eng.$('[data-kb-new]')) === null,
    'the create button is visible to a reader'
  )
  note(
    'the engineer gets no edit control on a row',
    (await rowAction(eng, docA, 'edit')) === 'missing',
    'an edit button is visible to a reader'
  )
  note(
    'the engineer gets no delete control on a row',
    (await rowAction(eng, docA, 'delete')) === 'missing',
    'a delete button is visible to a reader'
  )
  note(
    'the engineer can still download a document',
    (await rowAction(eng, docA, 'download')) === 'enabled',
    'the download button is missing for a reader'
  )

  await engineer.context.close()
} catch (err) {
  note('knowledge page run', false, err.message)
  const p = admin?.page ?? engineer?.page
  if (p) {
    try {
      await shot(p, 'error')
    } catch {
      /* ignore */
    }
  }
} finally {
  await admin?.context.close().catch(() => {})
  await engineer?.context.close().catch(() => {})
  await browser.close()
}

fs.writeFileSync(
  path.join(outDir, 'knowledge_report.json'),
  JSON.stringify({ docA, docB, created, steps }, null, 2)
)
const failed = steps.filter((s) => !s.ok).length
console.log('')
console.log(`  RESULT : ${failed === 0 ? 'PASS' : 'FAIL (' + failed + ')'}`)
if (failed !== 0) process.exit(1)
