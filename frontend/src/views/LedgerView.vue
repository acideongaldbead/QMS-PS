<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { errorMessage } from '@/api/http'
import { complaintApi, type LedgerQuery, type LedgerRow } from '@/api/complaints'
import { masterDataApi, type StatusCode } from '@/api/masterData'
import { useMetaStore } from '@/stores/meta'
import RowAction from '@/components/RowAction.vue'

const { t } = useI18n()
const route = useRoute()
const router = useRouter()
const meta = useMetaStore()

/** Stage order, used for the "n/9" progress next to the stage badge. */
const STAGES = ['D0', 'D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8']

const scope = ref<'mine' | 'all'>('mine')
const statuses = ref<StatusCode[]>([])
const advancedOpen = ref(false)

const filters = reactive({
  q: '',
  status: '',
  priority: '',
  customer: '',
  complaintType: '',
  owner: '',
  product: '',
  startFrom: '',
  startTo: '',
  targetFrom: '',
  targetTo: '',
  overdue: false,
  open: false,
  valid: false
})

const rows = ref<LedgerRow[]>([])
const total = ref(0)
const mineTotal = ref(0)
const allTotal = ref(0)
const page = ref(1)
const size = ref(20)
const sort = ref<string | null>(null)
const order = ref<'asc' | 'desc'>('desc')
const loading = ref(false)
const exporting = ref(false)
const selected = ref<LedgerRow[]>([])

/** Columns the user may hide. The complaint id stays visible: it is the anchor. */
const COLUMNS = [
  { key: 'status', label: '状态' },
  { key: 'stage', label: '8D 阶段' },
  { key: 'priority', label: '优先级' },
  { key: 'customer', label: '质量合作伙伴' },
  { key: 'product', label: '产品类型' },
  { key: 'startDate', label: '开始日期' },
  { key: 'targetDate', label: '目标日期' },
  { key: 'closeDate', label: '关闭日期' },
  { key: 'days', label: '处理天数' },
  { key: 'owner', label: '负责人' },
  { key: 'customerRefId', label: '客户参考ID' }
]
const hidden = reactive<Record<string, boolean>>({})

const scopeHint = computed(() =>
  scope.value === 'mine'
    ? '仅显示我承担负责人 / 协调人 / 验证负责人 / 报告负责人，或参与阶段任务的单据'
    : '显示我有权查看的全部数据（一期不做部门级数据隔离）'
)

const exportLabel = computed(() =>
  selected.value.length ? `导出选中 ${selected.value.length} 条` : '导出 Excel'
)

// ------------------------------------------------------------------ loading

/**
 * Only the non-empty filters are sent, so the server sees exactly what the form
 * shows. Sort keys must match the whitelist in ComplaintMapper.findLedger.
 */
function buildParams(): LedgerQuery {
  const params: LedgerQuery = { scope: scope.value }
  if (filters.q.trim()) params.q = filters.q.trim()
  if (filters.status) params.status = filters.status
  if (filters.priority) params.priority = filters.priority
  if (filters.customer) params.customer = filters.customer
  if (filters.complaintType) params.complaintType = filters.complaintType
  if (filters.owner) params.owner = filters.owner
  if (filters.product.trim()) params.product = filters.product.trim()
  if (filters.startFrom) params.startFrom = filters.startFrom
  if (filters.startTo) params.startTo = filters.startTo
  if (filters.targetFrom) params.targetFrom = filters.targetFrom
  if (filters.targetTo) params.targetTo = filters.targetTo
  if (filters.overdue) params.overdue = true
  if (filters.open) params.open = true
  if (filters.valid) params.valid = true
  if (sort.value) {
    params.sort = sort.value
    params.order = order.value
  }
  return params
}

async function load() {
  loading.value = true
  try {
    const data = await complaintApi.ledger({ ...buildParams(), page: page.value, size: size.value })
    rows.value = data.items ?? []
    total.value = data.total
    mineTotal.value = data.mineTotal
    allTotal.value = data.allTotal
    page.value = data.page
    size.value = data.size
  } catch (e) {
    ElMessage.error('台账加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

/** The tab and the keyword live in the URL so the top-bar search and a reload land here. */
function syncUrl() {
  const query: Record<string, string> = { scope: scope.value }
  if (filters.q.trim()) query.q = filters.q.trim()
  router.replace({ path: '/complaints', query })
}

function search() {
  page.value = 1
  syncUrl()
  load()
}

function resetFilters() {
  Object.assign(filters, {
    q: '',
    status: '',
    priority: '',
    customer: '',
    complaintType: '',
    owner: '',
    product: '',
    startFrom: '',
    startTo: '',
    targetFrom: '',
    targetTo: '',
    overdue: false,
    open: false,
    valid: false
  })
  search()
}

function switchScope(next: 'mine' | 'all') {
  if (scope.value === next) return
  scope.value = next
  search()
}

function onSortChange(payload: { prop: string; order: string | null }) {
  if (!payload.order) {
    sort.value = null
    order.value = 'desc'
  } else {
    sort.value = payload.prop
    order.value = payload.order === 'ascending' ? 'asc' : 'desc'
  }
  page.value = 1
  load()
}

function onSelectionChange(selection: LedgerRow[]) {
  selected.value = selection
}

function toggleColumn(key: string) {
  hidden[key] = !hidden[key]
}

// ------------------------------------------------------------------ export

function saveBlob(blob: Blob, fileName: string) {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  window.URL.revokeObjectURL(url)
}

/** Ticked rows win; with nothing ticked the whole current query is exported. */
async function exportExcel() {
  exporting.value = true
  try {
    const ids = selected.value.map((row) => row.complaintId)
    const blob = await complaintApi.exportLedger({
      ...buildParams(),
      ids: ids.length ? ids.join(',') : undefined
    })
    saveBlob(blob, 'complaint-ledger.xlsx')
    ElMessage.success(ids.length ? `已导出选中 ${ids.length} 条` : '已导出当前查询结果')
  } catch (e) {
    ElMessage.error('导出失败：' + errorMessage(e))
  } finally {
    exporting.value = false
  }
}

// ------------------------------------------------------------------ row rendering

function isOverdue(row: LedgerRow) {
  return row.overdueDays > 0 && !row.closeDate
}

function statusClass(row: LedgerRow) {
  if (row.closeDate) return 'is-done'
  return isOverdue(row) ? 'is-overdue' : 'is-active'
}

function stageBadgeClass(row: LedgerRow) {
  if (row.closeDate) return 'badge-success'
  return isOverdue(row) ? 'badge-danger' : 'badge-info'
}

/**
 * Progress is derived from the stage, not from counting sub-records. A complaint
 * closed as "not valid" goes straight from D2 to closed, so showing 9/9 for it
 * would claim work that never happened.
 */
function stageProgress(row: LedgerRow) {
  if (row.closeReasonCode === 'CLOSE_INVALID') return '已结案'
  if (row.closeDate) return '9/9'
  const index = STAGES.indexOf(row.currentStage)
  return index < 0 ? '—' : `${index + 1}/9`
}

function priorityClass(code: string) {
  if (code === 'PRIORITY_003') return 'p-critical'
  if (code === 'PRIORITY_002') return 'p-urgent'
  return 'p-standard'
}

function rowClass({ row }: { row: LedgerRow }) {
  return isOverdue(row) ? 'row-overdue' : ''
}

function openDetail(row: LedgerRow) {
  router.push({ name: 'complaintDetail', params: { id: row.complaintId } })
}

function copyComplaint(row: LedgerRow) {
  router.push({ name: 'complaintNew', query: { copyFrom: row.complaintId } })
}

// ------------------------------------------------------------------ lifecycle

async function loadStatuses() {
  try {
    statuses.value = await masterDataApi.statusCodes('Complaint')
  } catch (e) {
    ElMessage.error('投诉状态字典加载失败：' + errorMessage(e))
  }
}

onMounted(async () => {
  if (route.query.scope === 'all') scope.value = 'all'
  if (typeof route.query.q === 'string') filters.q = route.query.q
  await Promise.all([meta.ensureLoaded(), loadStatuses()])
  await load()
})

/** The top bar pushes a new ?q= while this page is already open. */
watch(
  () => route.query.q,
  (value) => {
    const next = typeof value === 'string' ? value : ''
    if (next === filters.q) return
    filters.q = next
    search()
  }
)
</script>

<template>
  <div>
    <div class="page-head">
      <div>
        <h1>{{ t('page.ledger') }}</h1>
      </div>
    </div>

    <el-card shadow="never">
      <!-- tabs + simple filters -->
      <div class="table-toolbar" style="gap: 16px">
        <div class="pill-tabs">
          <button class="pill-tab" :class="{ 'is-on': scope === 'mine' }" @click="switchScope('mine')">
            与我相关 <span class="count-pill">{{ mineTotal }}</span>
          </button>
          <button class="pill-tab" :class="{ 'is-on': scope === 'all' }" @click="switchScope('all')">
            全部数据 <span class="count-pill">{{ allTotal }}</span>
          </button>
        </div>
        <span class="fs-12 t-3">{{ scopeHint }}</span>
        <span class="grow"></span>
        <el-button size="small" text @click="advancedOpen = !advancedOpen">
          高级搜索 {{ advancedOpen ? '▲' : '▼' }}
        </el-button>
      </div>

      <div class="table-toolbar">
        <el-input
          v-model="filters.q"
          placeholder="模糊查询：流程ID / 客户参考ID / 客户名称 / 产品编码"
          clearable
          style="width: 300px"
          @keyup.enter="search"
        />
        <el-select v-model="filters.status" placeholder="全部状态" clearable style="width: 150px">
          <el-option v-for="s in statuses" :key="s.code" :label="s.nameCn" :value="s.code" />
        </el-select>
        <el-select v-model="filters.priority" placeholder="全部优先级" clearable style="width: 140px">
          <el-option v-for="p in meta.priorities" :key="p.code" :label="p.nameCn" :value="p.code" />
        </el-select>
        <el-select
          v-model="filters.customer"
          placeholder="全部客户"
          clearable
          filterable
          style="width: 200px"
        >
          <el-option v-for="c in meta.customers" :key="c.code" :label="c.name" :value="c.code" />
        </el-select>
        <span class="grow"></span>
        <el-button size="small" @click="resetFilters">重置</el-button>
        <el-button size="small" type="primary" @click="search">查询</el-button>
      </div>

      <!-- advanced search -->
      <div v-if="advancedOpen" class="table-toolbar" style="flex-wrap: wrap">
        <el-date-picker
          v-model="filters.startFrom"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="开始日期（起）"
          style="width: 160px"
        />
        <el-date-picker
          v-model="filters.startTo"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="开始日期（止）"
          style="width: 160px"
        />
        <el-date-picker
          v-model="filters.targetFrom"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="目标日期（起）"
          style="width: 160px"
        />
        <el-date-picker
          v-model="filters.targetTo"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="目标日期（止）"
          style="width: 160px"
        />
        <el-select
          v-model="filters.complaintType"
          placeholder="投诉类型"
          clearable
          style="width: 170px"
        >
          <el-option
            v-for="c in meta.complaintTypes"
            :key="c.code"
            :label="c.nameCn"
            :value="c.code"
          />
        </el-select>
        <el-select
          v-model="filters.owner"
          placeholder="投诉负责人"
          clearable
          filterable
          style="width: 160px"
        >
          <el-option v-for="e in meta.employees" :key="e.id" :label="e.name" :value="e.id" />
        </el-select>
        <el-input
          v-model="filters.product"
          placeholder="产品编码（12NC / 9NC）"
          clearable
          style="width: 200px"
        />
        <el-checkbox v-model="filters.overdue">仅看已超期单据</el-checkbox>
        <el-checkbox v-model="filters.open">仅看未结案单据</el-checkbox>
        <el-checkbox v-model="filters.valid">仅看投诉成立的单据</el-checkbox>
      </div>

      <!-- result tools -->
      <div class="table-toolbar">
        <span class="fs-12 t-3">
          共 <b class="t-1 num">{{ total }}</b> 条记录
        </span>
        <span class="grow"></span>
        <span class="fs-12 t-3">已选 <b class="t-1 num">{{ selected.length }}</b> 条</span>
        <el-popover placement="bottom-end" :width="180" trigger="click">
          <template #reference>
            <el-button size="small" text>列设置</el-button>
          </template>
          <div class="col-settings">
            <el-checkbox
              v-for="c in COLUMNS"
              :key="c.key"
              :model-value="!hidden[c.key]"
              @change="toggleColumn(c.key)"
            >
              {{ c.label }}
            </el-checkbox>
          </div>
        </el-popover>
        <el-button size="small" :loading="exporting" @click="exportExcel">{{ exportLabel }}</el-button>
      </div>

      <el-table
        v-loading="loading"
        :data="rows"
        row-key="complaintId"
        size="small"
        :row-class-name="rowClass"
        :empty-text="
          scope === 'mine'
            ? '「与我相关」页签下暂无单据，可切换到「全部数据」查看。'
            : '没有符合条件的投诉，请调整筛选条件后重试。'
        "
        @selection-change="onSelectionChange"
        @sort-change="onSortChange"
      >
        <el-table-column type="selection" width="40" />
        <el-table-column prop="id" label="流程ID" width="185" sortable="custom">
          <template #default="{ row }">
            <a class="mono fw-medium link" @click="openDetail(row)">{{ row.complaintId }}</a>
            <span v-if="row.mine" class="badge badge-primary" style="margin-left: 4px">我相关</span>
          </template>
        </el-table-column>
        <el-table-column v-if="!hidden.status" prop="status" label="状态" width="120" sortable="custom">
          <template #default="{ row }">
            <span class="status" :class="statusClass(row)">{{ row.statusName || row.statusCode }}</span>
          </template>
        </el-table-column>
        <el-table-column v-if="!hidden.stage" prop="stage" label="8D 阶段" width="120" sortable="custom">
          <template #default="{ row }">
            <span class="badge" :class="stageBadgeClass(row)">{{ row.currentStage }}</span>
            <span class="fs-11 t-3" style="margin-left: 5px">{{ stageProgress(row) }}</span>
          </template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.priority"
          prop="priority"
          label="优先级"
          width="110"
          sortable="custom"
        >
          <template #default="{ row }">
            <span class="prio" :class="priorityClass(row.priorityCode)">{{ row.priorityName }}</span>
          </template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.customer"
          prop="customer"
          label="质量合作伙伴"
          min-width="200"
          show-overflow-tooltip
          sortable="custom"
        >
          <template #default="{ row }">{{ row.customerName || '—' }}</template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.product"
          prop="product"
          label="产品类型"
          min-width="200"
          show-overflow-tooltip
          sortable="custom"
        >
          <template #default="{ row }">{{ row.productTypeName || row.productCode || '—' }}</template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.startDate"
          prop="startDate"
          label="开始日期"
          width="120"
          sortable="custom"
        >
          <template #default="{ row }">{{ row.startDate || '—' }}</template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.targetDate"
          prop="targetDate"
          label="目标日期"
          width="200"
          sortable="custom"
        >
          <template #default="{ row }">
            <span class="mono">{{ row.targetDate || '—' }}</span>
            <span v-if="isOverdue(row)" class="overdue-chip">超期 {{ row.overdueDays }} 天</span>
          </template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.closeDate"
          prop="closeDate"
          label="关闭日期"
          width="120"
          sortable="custom"
        >
          <template #default="{ row }">
            <span v-if="row.closeDate" class="mono">{{ row.closeDate }}</span>
            <span v-else class="t-3">未关闭</span>
          </template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.days"
          prop="days"
          label="处理天数"
          width="100"
          align="right"
          sortable="custom"
        >
          <template #default="{ row }">{{ row.processingDays ?? '—' }}</template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.owner"
          prop="owner"
          label="负责人"
          width="110"
          sortable="custom"
        >
          <template #default="{ row }">{{ row.ownerName || '—' }}</template>
        </el-table-column>
        <el-table-column
          v-if="!hidden.customerRefId"
          prop="customerRefId"
          label="客户参考ID"
          min-width="150"
          show-overflow-tooltip
          sortable="custom"
        >
          <template #default="{ row }">
            <span class="mono fs-12 t-2">{{ row.customerReferenceId || '—' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="96" fixed="right">
          <template #default="{ row }">
            <span class="row-acts">
              <RowAction act="view" icon="eye" label="查看" @click="openDetail(row)" />
              <RowAction act="copy" icon="copy" label="复制" @click="copyComplaint(row)" />
            </span>
          </template>
        </el-table-column>
      </el-table>

      <div class="table-toolbar" style="justify-content: flex-end">
        <el-pagination
          :current-page="page"
          :page-size="size"
          :page-sizes="[20, 50, 100]"
          :total="total"
          layout="total, sizes, prev, pager, next"
          @current-change="(p: number) => { page = p; load() }"
          @size-change="(s: number) => { size = s; page = 1; load() }"
        />
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.link {
  color: var(--c-primary);
  cursor: pointer;
}

.col-settings {
  display: flex;
  flex-direction: column;
  gap: 2px;
  max-height: 320px;
  overflow: auto;
}

/* The prototype marks an overdue row with a red rule down its first cell. */
:deep(.el-table__row.row-overdue td:first-child) {
  box-shadow: inset 3px 0 0 var(--c-danger);
}
</style>
