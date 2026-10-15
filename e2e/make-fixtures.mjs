/**
 * make-fixtures.mjs
 *
 * Generates the binary Office fixture the knowledge-centre preview test uploads.
 * Run it once and commit the output under fixtures/; it is not part of a normal
 * test run.
 *
 *   cd e2e
 *   npm install
 *   node make-fixtures.mjs
 *
 * Only the .pptx is generated here. The other two fixture files are real files
 * that already exist: the .docx is docs/templates/XTE-0071.docx, and the .xlsx is
 * downloaded live from the ledger export endpoint by ui-knowledge.ps1.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import PptxGenJS from 'pptxgenjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const outDir = path.join(here, 'fixtures')
fs.mkdirSync(outDir, { recursive: true })

const target = path.join(outDir, 'preview-sample.pptx')

const pptx = new PptxGenJS()
const slide = pptx.addSlide()
slide.addText('PPTX PREVIEW', { x: 0.5, y: 0.6, w: 9, h: 1.2, fontSize: 40, bold: true })
slide.addText('QMS knowledge-centre preview fixture', {
  x: 0.5,
  y: 2.2,
  w: 9,
  h: 0.8,
  fontSize: 20
})

await pptx.writeFile({ fileName: target })
console.log('wrote ' + target)
