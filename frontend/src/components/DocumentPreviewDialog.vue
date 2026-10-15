<script setup lang="ts">
import { computed, nextTick, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { errorMessage } from '@/api/http'
import { attachmentApi } from '@/api/attachments'

type SheetRow = (string | number | boolean | null)[]

/**
 * In-page preview for the Office formats a browser cannot display on its own
 * (docx / xlsx / pptx). The bytes come through the authenticated download
 * endpoint and are parsed in the browser: nothing is rendered on the server, and
 * the file never leaves the client -- which matters for the confidential
 * complaint material the knowledge centre holds.
 *
 * Each renderer is imported only when a preview actually opens, so none of them
 * reaches the knowledge-centre or login bundle (the same shape RichTextEditor
 * and WhyMindMap use, and e2e/lazy-load.mjs asserts it).
 */
const props = defineProps<{
  modelValue: boolean
  attachmentId: number | null
  fileName: string
  fileSize?: number | null
}>()
const emit = defineEmits<{ 'update:modelValue': [value: boolean] }>()

const { t } = useI18n()

/** Parsing a huge deck in the browser would hang the tab, so past this we only offer the download. */
const MAX_PREVIEW_BYTES = 25 * 1024 * 1024

const visible = computed({
  get: () => props.modelValue,
  set: (value: boolean) => emit('update:modelValue', value)
})

const host = ref<HTMLElement | null>(null)
const loading = ref(false)
const error = ref('')
const sheetNames = ref<string[]>([])
const sheets = ref<SheetRow[][]>([])
const activeSheet = ref(0)

const extension = computed(() => {
  const name = props.fileName ?? ''
  const dot = name.lastIndexOf('.')
  return dot < 0 ? '' : name.slice(dot + 1).toLowerCase()
})

const tooLarge = computed(() => (props.fileSize ?? 0) > MAX_PREVIEW_BYTES)

function reset() {
  loading.value = false
  error.value = ''
  sheetNames.value = []
  sheets.value = []
  activeSheet.value = 0
  if (host.value) host.value.innerHTML = ''
}

/**
 * docx-preview / pptx-preview build real elements (not v-html) and a document may
 * carry hyperlinks: keep only safe schemes, and open what remains away from the app.
 */
function neutralizeLinks(root: HTMLElement) {
  root.querySelectorAll('a[href]').forEach((anchor) => {
    const href = anchor.getAttribute('href') ?? ''
    if (!/^(https?:|mailto:)/i.test(href)) {
      anchor.removeAttribute('href')
      return
    }
    anchor.setAttribute('target', '_blank')
    anchor.setAttribute('rel', 'noopener noreferrer')
  })
}

async function renderDocx(bytes: ArrayBuffer, target: HTMLElement) {
  const { renderAsync } = await import('docx-preview')
  await renderAsync(bytes, target, undefined, {
    inWrapper: true,
    ignoreWidth: true,
    breakPages: false
  })
  neutralizeLinks(target)
}

async function renderXlsx(bytes: ArrayBuffer) {
  const { default: readXlsxFile } = await import('read-excel-file/browser')
  const parsed = await readXlsxFile(bytes)
  sheetNames.value = parsed.map((s) => s.sheet)
  sheets.value = parsed.map((s) => s.data as SheetRow[])
}

async function renderPptx(bytes: ArrayBuffer, target: HTMLElement) {
  const { init } = await import('pptx-preview')
  const width = Math.max(target.clientWidth || 900, 320)
  const previewer = init(target, { width, height: Math.round((width * 9) / 16) })
  await previewer.preview(bytes)
  neutralizeLinks(target)
}

/** el-dialog destroys its body on close, so the host only exists once @opened fires. */
async function load() {
  reset()
  if (props.attachmentId == null) {
    error.value = t('kb.previewFailed')
    return
  }
  if (tooLarge.value) {
    return // the template shows the download-only state
  }

  loading.value = true
  try {
    const bytes = await (await attachmentApi.fetchBlob(props.attachmentId)).arrayBuffer()
    await nextTick()
    const target = host.value
    if (extension.value === 'docx') {
      await renderDocx(bytes, target as HTMLElement)
    } else if (extension.value === 'xlsx') {
      await renderXlsx(bytes)
    } else if (extension.value === 'pptx') {
      await renderPptx(bytes, target as HTMLElement)
    } else {
      error.value = t('kb.previewUnsupported')
    }
  } catch (e) {
    error.value = errorMessage(e)
  } finally {
    loading.value = false
  }
}

function download() {
  if (props.attachmentId != null) {
    attachmentApi.downloadAndSave(props.attachmentId, props.fileName)
  }
}
</script>

<template>
  <el-dialog
    v-model="visible"
    :title="fileName || t('kb.previewTitle')"
    width="1000px"
    top="6vh"
    destroy-on-close
    @opened="load"
    @closed="reset"
  >
    <div
      v-loading="loading"
      :element-loading-text="t('kb.previewLoading')"
      class="doc-preview"
      data-doc-preview
    >
      <div v-if="error || tooLarge" class="doc-preview-hint">
        <div>{{ tooLarge ? t('kb.previewTooLarge') : error }}</div>
        <el-button type="primary" class="doc-preview-action" data-doc-download @click="download">
          {{ t('kb.previewDownload') }}
        </el-button>
      </div>

      <template v-else>
        <div v-if="sheets.length" class="doc-sheets">
          <div v-if="sheetNames.length > 1" class="doc-sheet-tabs">
            <button
              v-for="(name, index) in sheetNames"
              :key="name"
              type="button"
              class="badge"
              :class="index === activeSheet ? 'badge-primary' : 'badge-neutral'"
              :data-sheet="index"
              @click="activeSheet = index"
            >
              {{ name }}
            </button>
          </div>
          <div class="doc-table-wrap">
            <table class="doc-table" data-doc-sheet-table>
              <tbody>
                <tr v-for="(row, r) in sheets[activeSheet]" :key="r">
                  <td v-for="(cell, c) in row" :key="c" :class="{ 'is-head': r === 0 }">
                    {{ cell === null || cell === undefined ? '' : cell }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- docx / pptx render their own DOM into this host -->
        <div v-show="!sheets.length" ref="host" class="doc-host" data-doc-host />
      </template>
    </div>
  </el-dialog>
</template>

<style scoped>
.doc-preview {
  min-height: 320px;
  max-height: 74vh;
  overflow: auto;
}

.doc-preview-hint {
  padding: var(--sp-6) var(--sp-4);
  text-align: center;
  color: var(--t-3);
  font-size: var(--fs-13);
}

.doc-preview-action {
  margin-top: var(--sp-4);
}

.doc-sheet-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: var(--sp-2);
  margin-bottom: var(--sp-2);
}

.doc-sheet-tabs .badge {
  cursor: pointer;
}

.doc-table-wrap {
  max-height: 66vh;
  overflow: auto;
  border: 1px solid var(--bd-1);
  border-radius: var(--r-2);
}

.doc-table {
  border-collapse: collapse;
  font-size: var(--fs-12);
}

.doc-table td {
  max-width: 320px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  padding: 4px 8px;
  border: 1px solid var(--bd-1);
}

.doc-table td.is-head {
  position: sticky;
  top: 0;
  background: var(--n-25);
  font-weight: var(--fw-semi);
  color: var(--t-1);
}

/* docx-preview draws a grey page background and drop shadows that clash with the dialog. */
.doc-host :deep(.docx-wrapper) {
  background: none;
  padding: 0;
}

.doc-host :deep(.docx-wrapper > section.docx) {
  box-shadow: none;
  margin: 0 auto var(--sp-4);
}
</style>
