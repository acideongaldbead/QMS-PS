<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage, ElMessageBox } from 'element-plus'
import { errorMessage } from '@/api/http'
import {
  knowledgeApi,
  type KnowledgeArticle,
  type KnowledgeSaveRequest,
  type KnowledgeSummary
} from '@/api/knowledge'
import { attachmentApi, formatBytes } from '@/api/attachments'
import { useAuthStore } from '@/stores/auth'
import { useMetaStore } from '@/stores/meta'
import QmsIcon from '@/components/QmsIcon.vue'
import AttachmentPanel from '@/components/AttachmentPanel.vue'
import DocumentPreviewDialog from '@/components/DocumentPreviewDialog.vue'

const { t, locale } = useI18n()
const auth = useAuthStore()
const meta = useMetaStore()

/** Reading is open to every role; maintaining is the administrator (requirement 3.11). */
const canManage = computed(() => auth.can('knowledge:manage'))
const isZh = computed(() => locale.value.startsWith('zh'))

const rows = ref<KnowledgeArticle[]>([])
const summary = ref<KnowledgeSummary>({ total: 0, categories: [] })
const loading = ref(false)

/** Empty string means "all categories" -- the server treats it as no filter. */
const activeCategory = ref('')
const keyword = ref('')

/** The document opened in the in-page Office preview, if any. */
const previewOpen = ref(false)
const previewAttachmentId = ref<number | null>(null)
const previewFileName = ref('')
const previewFileSize = ref<number | null>(null)

const dialogOpen = ref(false)
const editingId = ref<number | null>(null)
const saving = ref(false)
const form = reactive({
  title: '',
  titleEn: '',
  category: '',
  docCode: '',
  version: '',
  summary: '',
  content: ''
})

/**
 * The sidebar always shows every dictionary category, including the empty ones,
 * so a category the administrator just added is visible before it holds anything.
 */
const categoryTabs = computed(() => {
  const counts = new Map(summary.value.categories.map((c) => [c.category, c.total]))
  return [
    { code: '', label: t('kb.all'), count: summary.value.total },
    ...meta.knowledgeCategories.map((c) => ({
      code: c.code,
      label: isZh.value ? c.nameCn : c.nameEn || c.nameCn,
      count: counts.get(c.code) ?? 0
    }))
  ]
})

/**
 * The rows arrive ordered by the dictionary, so grouping consecutive rows keeps
 * that order without a second ordering table here.
 */
const groups = computed(() => {
  const out: { code: string; label: string; items: KnowledgeArticle[] }[] = []
  for (const row of rows.value) {
    let group = out.find((g) => g.code === row.category)
    if (!group) {
      group = { code: row.category, label: rowCategoryLabel(row), items: [] }
      out.push(group)
    }
    group.items.push(row)
  }
  return out
})

const listHeading = computed(
  () =>
    (activeCategory.value ? categoryLabel(activeCategory.value) : t('kb.allCategories')) +
    ' · ' +
    t('kb.docCount', { n: rows.value.length })
)

function categoryLabel(code: string): string {
  const item = meta.knowledgeCategories.find((c) => c.code === code)
  if (!item) return code
  return isZh.value ? item.nameCn : item.nameEn || item.nameCn
}

/** Both title columns are kept; the list shows the one matching the language. */
function titleOf(row: KnowledgeArticle): string {
  return isZh.value ? row.title : row.titleEn || row.title
}

function rowCategoryLabel(row: KnowledgeArticle): string {
  if (isZh.value) return row.categoryName || row.category
  return row.categoryNameEn || row.categoryName || row.category
}

function fileExtension(row: KnowledgeArticle): string {
  const name = row.latestFileName ?? ''
  const dot = name.lastIndexOf('.')
  return dot < 0 ? '' : name.slice(dot + 1).toLowerCase()
}

/** Drives the coloured file chip; unknown kinds fall back to the neutral one. */
function fileIconClass(row: KnowledgeArticle): string {
  const ext = fileExtension(row)
  if (ext === 'pdf') return 'pdf'
  if (['xls', 'xlsx', 'csv'].includes(ext)) return 'xls'
  if (['doc', 'docx', 'ppt', 'pptx', 'txt', 'zip'].includes(ext)) return 'doc'
  if (['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'].includes(ext)) return 'img'
  return ''
}

function fileIconText(row: KnowledgeArticle): string {
  return (fileExtension(row) || '—').slice(0, 4).toUpperCase()
}

/** Formats the browser renders natively, opened in a new tab. */
const NATIVE_EXT = ['pdf', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp']
/** Office formats rendered in-page by DocumentPreviewDialog. */
const OFFICE_EXT = ['docx', 'xlsx', 'pptx']

/**
 * The preview control is live whenever the row has a file: the formats we cannot
 * render fall through to a "please download" message rather than a dead button.
 */
function canPreview(row: KnowledgeArticle): boolean {
  return row.latestAttachmentId != null
}

function formatDate(value?: string | null): string {
  return value ? value.slice(0, 10) : '—'
}

async function load() {
  loading.value = true
  try {
    const [list, counts] = await Promise.all([
      knowledgeApi.list({
        category: activeCategory.value || undefined,
        keyword: keyword.value.trim() || undefined
      }),
      knowledgeApi.summary()
    ])
    rows.value = list
    summary.value = counts
  } catch (e) {
    ElMessage.error(t('kb.loadFailed') + errorMessage(e))
  } finally {
    loading.value = false
  }
}

function selectCategory(code: string) {
  activeCategory.value = code
  load()
}

function search() {
  load()
}

async function preview(row: KnowledgeArticle) {
  if (!canPreview(row)) {
    ElMessage.info(t('kb.previewUnsupported'))
    return
  }
  const ext = fileExtension(row)
  try {
    if (NATIVE_EXT.includes(ext)) {
      // PDF and images have a native viewer, so a new tab beats an in-app frame.
      await attachmentApi.openInNewTab(row.latestAttachmentId as number)
    } else if (OFFICE_EXT.includes(ext)) {
      previewAttachmentId.value = row.latestAttachmentId as number
      previewFileName.value = row.latestFileName ?? titleOf(row)
      previewFileSize.value = row.latestFileSize ?? null
      previewOpen.value = true
    } else {
      ElMessage.info(t('kb.previewUnsupported'))
    }
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

async function download(row: KnowledgeArticle) {
  if (row.latestAttachmentId == null || !row.latestFileName) {
    ElMessage.info(t('kb.noAttachment'))
    return
  }
  try {
    await attachmentApi.downloadAndSave(row.latestAttachmentId, row.latestFileName)
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

function openNew() {
  editingId.value = null
  Object.assign(form, {
    title: '',
    titleEn: '',
    category: meta.knowledgeCategories[0]?.code ?? '',
    docCode: '',
    version: '',
    summary: '',
    content: ''
  })
  dialogOpen.value = true
}

/**
 * The attachment panel needs an id, so a new document is saved first and its
 * files uploaded on the next edit -- the dialog says as much.
 */
function openEdit(row: KnowledgeArticle) {
  editingId.value = row.articleId
  Object.assign(form, {
    title: row.title,
    titleEn: row.titleEn ?? '',
    category: row.category,
    docCode: row.docCode ?? '',
    version: row.version ?? '',
    summary: row.summary ?? '',
    content: row.content ?? ''
  })
  dialogOpen.value = true
}

async function save() {
  if (!form.title.trim()) {
    ElMessage.warning(t('kb.colTitle'))
    return
  }
  if (!form.category) {
    ElMessage.warning(t('kb.colCategory'))
    return
  }
  saving.value = true
  try {
    const body: KnowledgeSaveRequest = { ...form }
    if (editingId.value == null) {
      await knowledgeApi.create(body)
    } else {
      await knowledgeApi.update(editingId.value, body)
    }
    ElMessage.success(t('kb.saved'))
    dialogOpen.value = false
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}

/**
 * The dialog is also where files are added, and the upload panel refreshes only
 * itself -- so the rows are re-read once it closes, whether or not anything was
 * saved.
 */
function onDialogClosed() {
  load()
}

async function remove(row: KnowledgeArticle) {
  try {
    await ElMessageBox.confirm(t('kb.deleteConfirm', { title: row.title }), t('kb.del'), {
      type: 'warning',
      confirmButtonText: t('common.confirm'),
      cancelButtonText: t('common.cancel')
    })
  } catch {
    return
  }
  try {
    await knowledgeApi.remove(row.articleId)
    ElMessage.success(t('kb.deleted'))
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  }
}

onMounted(async () => {
  await meta.ensureLoaded()
  await load()
})
</script>

<template>
  <div v-loading="loading">
    <div class="page-head">
      <div class="page-title-row">
        <div>
          <h1 class="page-title">{{ t('page.kb') }}</h1>
          <div class="page-sub">{{ t('kb.sub') }}</div>
        </div>
        <div v-if="canManage" class="page-actions">
          <el-button type="primary" data-kb-new @click="openNew">
            <QmsIcon name="plus" :size="14" />
            <span>{{ t('kb.newDoc') }}</span>
          </el-button>
        </div>
      </div>
    </div>

    <div class="grid grid-sidebar">
      <section>
        <div class="card">
          <div class="card-head">
            <div>
              <div class="card-title">{{ t('kb.allDocs') }}</div>
              <div class="card-sub" data-kb-heading>{{ listHeading }}</div>
            </div>
            <div class="card-head-actions">
              <span data-kb-search>
                <el-input
                  v-model="keyword"
                  :placeholder="t('kb.searchPlaceholder')"
                  clearable
                  style="width: 240px"
                  @keyup.enter="search"
                  @clear="search"
                />
              </span>
            </div>
          </div>

          <div class="card-body flush">
            <template v-for="group in groups" :key="group.code">
              <div class="table-toolbar kb-group-head">
                <span class="fw-semi t-1 fs-13">{{ group.label }}</span>
                <span class="count-pill">{{ group.items.length }}</span>
              </div>

              <div
                v-for="row in group.items"
                :key="row.articleId"
                class="file-item kb-row"
                :data-doc="row.articleId"
              >
                <span class="file-icon" :class="fileIconClass(row)">{{ fileIconText(row) }}</span>

                <span class="kb-main">
                  <span class="kb-line">
                    <span class="kb-title t-1 fs-13 fw-medium" :title="titleOf(row)" data-kb-title>{{
                      titleOf(row)
                    }}</span>
                    <span v-if="row.docCode" class="kb-code mono fs-11 t-3">{{ row.docCode }}</span>
                    <span v-if="row.version" class="kb-badge badge badge-neutral">{{
                      row.version
                    }}</span>
                  </span>
                  <span v-if="row.summary" class="fs-11 t-3 kb-summary">{{ row.summary }}</span>
                </span>

                <span class="file-meta kb-size">
                  <span class="kb-size-line">
                    <template v-if="row.latestFileName">
                      {{ formatBytes(row.latestFileSize || 0) }}　·
                    </template>
                    {{ formatDate(row.updatedAt) }}
                  </span>
                  <span class="fs-11 t-4">
                    {{ t('kb.maintainer') }} {{ row.maintainerName || '—' }}
                  </span>
                </span>

                <span class="file-act">
                  <button
                    :title="t('kb.preview')"
                    :disabled="!canPreview(row)"
                    data-act="preview"
                    @click="preview(row)"
                  >
                    <QmsIcon name="eye" :size="13" />
                  </button>
                  <button :title="t('kb.download')" data-act="download" @click="download(row)">
                    <QmsIcon name="download" :size="13" />
                  </button>
                  <button
                    v-if="canManage"
                    :title="t('kb.edit')"
                    data-act="edit"
                    @click="openEdit(row)"
                  >
                    <QmsIcon name="file" :size="13" />
                  </button>
                  <button
                    v-if="canManage"
                    :title="t('kb.del')"
                    data-act="delete"
                    @click="remove(row)"
                  >
                    <QmsIcon name="logout" :size="13" />
                  </button>
                </span>
              </div>
            </template>

            <div v-if="!rows.length" class="empty">
              <div class="empty-art"><QmsIcon name="book" :size="26" /></div>
              <div class="empty-title">{{ t('kb.emptyTitle') }}</div>
              <div class="empty-text">{{ t('kb.emptyText') }}</div>
            </div>
          </div>
        </div>
      </section>

      <aside>
        <div class="card">
          <div class="card-head tinted">
            <div><div class="card-title">{{ t('kb.categoryTitle') }}</div></div>
          </div>
          <div class="card-body tight kb-cats">
            <button
              v-for="tab in categoryTabs"
              :key="tab.code || 'all'"
              class="menu-item"
              :class="{ 'is-on': activeCategory === tab.code }"
              :data-cat="tab.code"
              @click="selectCategory(tab.code)"
            >
              <QmsIcon name="book" :size="14" />
              <span class="grow">{{ tab.label }}</span>
              <span class="count-pill">{{ tab.count }}</span>
            </button>
          </div>
        </div>
      </aside>
    </div>

    <el-dialog
      v-model="dialogOpen"
      :title="editingId == null ? t('kb.newDoc') : t('kb.editDoc')"
      width="1000px"
      @closed="onDialogClosed"
    >
      <el-form label-width="96px" label-position="left">
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item :label="t('kb.colTitle')" required>
              <div class="kb-field" data-kb-field-title>
                <el-input v-model="form.title" maxlength="255" />
              </div>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item :label="t('kb.colTitleEn')">
              <el-input v-model="form.titleEn" maxlength="255" />
            </el-form-item>
          </el-col>
        </el-row>

        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item :label="t('kb.colCategory')" required>
              <div class="kb-field" data-kb-field-category>
                <el-select v-model="form.category" style="width: 100%">
                  <el-option
                    v-for="c in meta.knowledgeCategories"
                    :key="c.code"
                    :label="isZh ? c.nameCn : c.nameEn || c.nameCn"
                    :value="c.code"
                  />
                </el-select>
              </div>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item :label="t('kb.colDocCode')">
              <div class="kb-field" data-kb-field-code>
                <el-input v-model="form.docCode" maxlength="32" />
              </div>
            </el-form-item>
          </el-col>
        </el-row>

        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item :label="t('kb.colVersion')">
              <div class="kb-field" data-kb-field-version>
                <el-input v-model="form.version" maxlength="16" />
              </div>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item :label="t('kb.colSummary')">
              <div class="kb-field" data-kb-field-summary>
                <el-input v-model="form.summary" maxlength="500" />
              </div>
            </el-form-item>
          </el-col>
        </el-row>

        <el-form-item :label="t('kb.colContent')">
          <el-input v-model="form.content" type="textarea" :rows="3" />
        </el-form-item>
      </el-form>

      <div v-if="editingId != null" class="kb-files" data-kb-files>
        <div class="kb-files-title">{{ t('kb.docFiles') }}</div>
        <div class="fs-11 t-3 mb-2">{{ t('kb.attachmentHint') }}</div>
        <AttachmentPanel biz-type="KnowledgeArticle" :biz-id="String(editingId)" />
      </div>
      <div v-else class="kb-files-hint fs-11 t-3">{{ t('kb.attachmentHint') }}</div>

      <template #footer>
        <el-button @click="dialogOpen = false">{{ t('common.cancel') }}</el-button>
        <el-button type="primary" :loading="saving" data-kb-save @click="save">
          {{ t('common.save') }}
        </el-button>
      </template>
    </el-dialog>

    <DocumentPreviewDialog
      v-model="previewOpen"
      :attachment-id="previewAttachmentId"
      :file-name="previewFileName"
      :file-size="previewFileSize"
    />
  </div>
</template>

<style scoped>
/*
  The shared .grid-sidebar stacks into one column below 1280px. For a filter
  sidebar that is exactly the wrong move: the category list ends up under the
  document list, below the fold. This page narrows the column instead and keeps
  the two side by side until 1100px, the same trade the home page makes.
*/
.grid-sidebar {
  grid-template-columns: minmax(0, 1fr) 300px;
}

@media (max-width: 1100px) {
  .grid-sidebar {
    grid-template-columns: minmax(0, 1fr);
  }
}

.kb-group-head {
  background: var(--n-25);
  border-top: 1px solid var(--bd-1);
}

/*
  .file-item is the prototype's anchor styling. As a div it keeps the flex row but
  needs its own padding and alignment, and the rows read as one continuous list.
*/
.kb-row {
  border-radius: 0;
  border-bottom: 1px solid var(--bd-1);
  padding: 10px var(--sp-4);
  align-items: center;
}

.kb-row:last-child {
  border-bottom: none;
}

.kb-main {
  flex: 1 1 auto;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.kb-line {
  display: flex;
  align-items: center;
  gap: var(--sp-2);
  min-width: 0;
}

/*
  A long title gives way; the code and the version badge keep their shape. Left
  to the flex defaults both shrink and their own text wraps mid-token, which is
  what a narrow window used to show.
*/
.kb-title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.kb-code,
.kb-badge {
  flex: 0 0 auto;
}

.kb-summary {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.kb-size {
  min-width: 140px;
  text-align: right;
  display: flex;
  flex-direction: column;
  gap: 1px;
  line-height: 1.4;
}

.kb-size-line {
  font-family: var(--font-num);
}

.kb-cats {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

/* Wraps each dialog control so the form-item column is filled, and gives the
   UI script a stable hook: Element Plus forwards fallthrough attributes onto
   the inner <input>, so anchoring on the control itself is not reliable. */
.kb-field {
  width: 100%;
}

.kb-row .file-act button:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

.kb-row .file-act button:disabled:hover {
  background: none;
  color: var(--t-4);
}

.kb-files {
  margin-top: var(--sp-2);
  border-top: 1px solid var(--bd-1);
  padding-top: var(--sp-3);
}

.kb-files-title {
  font-size: var(--fs-13);
  font-weight: var(--fw-semi);
  color: var(--t-1);
  margin-bottom: 2px;
}

.kb-files-hint {
  margin-top: var(--sp-2);
  border-top: 1px solid var(--bd-1);
  padding-top: var(--sp-3);
}
</style>
