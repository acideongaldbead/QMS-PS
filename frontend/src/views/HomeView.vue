<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { errorMessage } from '@/api/http'
import { homeApi, type Announcement, type HomeOverview, type TodoItem } from '@/api/home'

const { t } = useI18n()
const router = useRouter()

const overview = ref<HomeOverview | null>(null)
const announcements = ref<Announcement[]>([])
const loading = ref(false)
const drawerOpen = ref(false)
const activeAnnouncement = ref<Announcement | null>(null)

const todos = computed(() => overview.value?.todos ?? [])
const todoTotal = computed(() => overview.value?.todoTotal ?? 0)
const overdueRows = computed(() => overview.value?.overdueComplaints ?? [])
const overdueTotal = computed(() => overview.value?.overdueComplaintTotal ?? 0)

/**
 * Groups the capped list. The server already ordered the entries by type, so the
 * groups come out in the intended order without a second ordering table here.
 */
const todoGroups = computed(() => {
  const groups: { label: string; items: TodoItem[]; overdue: number }[] = []
  for (const item of todos.value) {
    let group = groups.find((g) => g.label === item.typeLabel)
    if (!group) {
      group = { label: item.typeLabel, items: [], overdue: 0 }
      groups.push(group)
    }
    group.items.push(item)
    if (item.overdueDays > 0) group.overdue += 1
  }
  return groups
})

/** The four figures, in the prototype's order and wording. */
const tiles = computed(() => {
  const stats = overview.value?.stats
  const urgent = stats?.overdueTaskCount ?? 0
  const pending = stats?.pendingApprovalCount ?? 0
  return [
    {
      label: '我的待办',
      value: stats?.todoCount ?? 0,
      unit: '项',
      foot: `覆盖 ${stats?.todoTypeCount ?? 0} 类任务`,
      tone: ''
    },
    {
      label: '已超期 / 紧急',
      value: urgent,
      unit: '项',
      foot: urgent > 0 ? '需优先处理' : '暂无',
      tone: urgent > 0 ? 'danger' : ''
    },
    {
      label: '待我审批',
      value: pending,
      unit: '份',
      foot: '8D 报告审批（走 OA 审批流）',
      tone: pending > 0 ? 'warning' : ''
    },
    {
      label: '与我相关投诉',
      value: stats?.myComplaintCount ?? 0,
      unit: '单',
      foot: '我承担负责人 / 协调人 / 验证负责人 / 报告负责人',
      tone: ''
    }
  ]
})

const todayLine = computed(() => {
  const now = new Date()
  const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][now.getDay()]
  const iso = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(
    now.getDate()
  ).padStart(2, '0')}`
  return `${iso} · 今天是${week}，以下是分配给你的待办任务`
})

function toneColor(tone: string) {
  if (tone === 'danger') return 'var(--c-danger)'
  if (tone === 'warning') return 'var(--c-warning)'
  return 'var(--t-1)'
}

function formatDateTime(value?: string | null) {
  return value ? value.replace('T', ' ').slice(0, 16) : '—'
}

async function load() {
  loading.value = true
  try {
    const [overviewData, announcementData] = await Promise.all([
      homeApi.overview(),
      homeApi.announcements(20)
    ])
    overview.value = overviewData
    announcements.value = announcementData
  } catch (e) {
    ElMessage.error('工作台加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

/** The entry lands on the tab of the complaint the work belongs to. */
function openTodo(item: TodoItem) {
  router.push({
    name: 'complaintDetail',
    params: { id: item.complaintId },
    query: { tab: item.tab }
  })
}

function openComplaint(complaintId: string) {
  router.push({ name: 'complaintDetail', params: { id: complaintId } })
}

function openLedger() {
  router.push({ path: '/complaints' })
}

/**
 * Opening an announcement also clears its NEW badge, server side so another
 * device does not show it again. The badge is cleared locally first: the reader
 * has seen it either way, and a failed call is reported rather than swallowed.
 */
async function openAnnouncement(announcement: Announcement) {
  activeAnnouncement.value = announcement
  drawerOpen.value = true
  if (!announcement.isNew) return

  announcement.isNew = false
  try {
    await homeApi.markAnnouncementRead(announcement.announcementId)
  } catch (e) {
    ElMessage.warning('公告已读状态未记录：' + errorMessage(e))
  }
}

onMounted(load)
</script>

<template>
  <div v-loading="loading">
    <div class="page-head">
      <div>
        <h1>{{ t('page.home') }}</h1>
        <div class="fs-12 t-3">{{ todayLine }}</div>
      </div>
    </div>

    <!-- figures on the left, announcements on the right, equal heights -->
    <div class="home-grid">
      <div class="grid grid-2">
        <div v-for="tile in tiles" :key="tile.label" class="stat">
          <div class="stat-label">{{ tile.label }}</div>
          <div class="stat-value" :style="{ color: toneColor(tile.tone) }">
            {{ tile.value }}<span class="unit">{{ tile.unit }}</span>
          </div>
          <div class="stat-foot">
            <span
              class="fs-11"
              :style="{ color: tile.tone ? toneColor(tile.tone) : 'var(--t-3)' }"
            >
              {{ tile.foot }}
            </span>
          </div>
        </div>
      </div>

      <el-card shadow="never" class="ann-card">
        <template #header>
          <div class="row-between">
            <span class="fw-semi">{{ t('top.notice') }}</span>
            <span class="fs-12 t-3">{{ announcements.length }} 条公告</span>
          </div>
        </template>
        <div class="file-list" style="margin: 0">
          <button
            v-for="item in announcements"
            :key="item.announcementId"
            class="file-item ann-item"
            @click="openAnnouncement(item)"
          >
            <span class="file-name" style="display: flex; flex-direction: column; gap: 3px">
              <span class="t-1 fs-13 fw-medium">
                <span v-if="item.isNew" class="new-chip">NEW</span>{{ item.title }}
              </span>
              <span class="fs-11 t-3">
                {{ formatDateTime(item.publishedAt) }} · {{ item.publishedByName || '—' }}
              </span>
            </span>
          </button>
          <div v-if="!announcements.length" class="fs-13 t-3" style="padding: var(--sp-4)">
            暂无公告
          </div>
        </div>
      </el-card>
    </div>

    <!-- overdue banner, full width -->
    <div v-if="overdueTotal > 0" class="alert alert-danger mt-4">
      <div class="alert-body">
        <div class="alert-title">
          有 {{ overdueTotal }} 单投诉已超出目标日期<template v-if="overdueTotal > overdueRows.length"
            >，其中超期最久的 {{ overdueRows.length }} 单如下</template
          >
        </div>
        <div class="muted fs-12 mt-1">
          <template v-for="(row, index) in overdueRows" :key="row.complaintId">
            <a class="mono" style="cursor: pointer" @click="openComplaint(row.complaintId)">{{
              row.complaintId
            }}</a>
            超期 {{ row.overdueDays }} 天<template v-if="index < overdueRows.length - 1">　·　</template>
          </template>
          <span v-if="overdueTotal > overdueRows.length">　…等共 {{ overdueTotal }} 单</span>
        </div>
      </div>
      <el-button size="small" type="danger" plain @click="openLedger">查看汇总</el-button>
    </div>

    <!-- to-do, full width -->
    <el-card shadow="never" class="mt-4">
      <template #header>
        <div class="row-between">
          <span class="fw-semi">{{ t('top.todo') }}</span>
          <span class="fs-12 t-3">
            共 {{ todoTotal }} 项{{
              todoTotal > todos.length ? `，按紧急程度显示前 ${todos.length} 项` : ''
            }}
          </span>
        </div>
      </template>

      <div v-if="!todos.length" class="empty-todo">
        当前没有待办事项，你负责的失效分析、报告审批与措施跟踪均已完成。
        <el-button link type="primary" @click="openLedger">浏览问题解决汇总</el-button>
      </div>

      <template v-for="group in todoGroups" :key="group.label">
        <div class="table-toolbar todo-group-head">
          <span class="fw-semi t-1 fs-13">{{ group.label }}</span>
          <span class="count-pill" :class="{ 'is-danger': group.overdue > 0 }">{{
            group.items.length
          }}</span>
          <span v-if="group.overdue > 0" class="fs-11 t-danger">
            其中 {{ group.overdue }} 项已超期
          </span>
        </div>
        <div class="file-list" style="margin: 0">
          <button
            v-for="item in group.items"
            :key="item.todoId"
            class="file-item todo-item"
            :data-todo="item.type"
            @click="openTodo(item)"
          >
            <span class="file-name" style="display: flex; flex-direction: column; gap: 1px">
              <span class="t-1 fs-13">{{ item.title }}</span>
              <span class="fs-11 t-3">
                关联 {{ item.complaintId }} · 状态 {{ item.statusText }}
              </span>
            </span>
            <span class="file-meta" style="min-width: 150px; text-align: right">
              <span v-if="item.overdueDays > 0" class="overdue-chip">
                {{ item.dueDate }} 超期 {{ item.overdueDays }} 天
              </span>
              <span v-else-if="item.dueDate" class="mono fs-11 t-3">{{ item.dueDate }}</span>
            </span>
          </button>
        </div>
      </template>
    </el-card>

    <el-drawer v-model="drawerOpen" :title="activeAnnouncement?.title || ''" size="480px">
      <div class="fs-12 t-3 mb-3">
        {{ formatDateTime(activeAnnouncement?.publishedAt) }} · 发布人
        {{ activeAnnouncement?.publishedByName || '—' }}
      </div>
      <!-- The body is sanitised HTML on the server (see HtmlSanitizer), so it is
           rendered rather than escaped. -->
      <div class="fs-13 ann-body" v-html="activeAnnouncement?.content"></div>
    </el-drawer>
  </div>
</template>

<style scoped>
/*
  Figures and announcements sit side by side and stay the same height. The right
  column narrows rather than stacking, because stacking was what made the layout
  unreadable on a laptop at 125% scaling.
*/
.home-grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 360px;
  gap: var(--sp-4);
  align-items: stretch;
}

@media (max-width: 1280px) {
  .home-grid {
    grid-template-columns: minmax(0, 1fr) 300px;
  }
}

@media (max-width: 1024px) {
  .home-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

.ann-card :deep(.el-card__body) {
  padding: 0;
}

/*
  .file-item is the prototype's anchor styling; as a button it would inherit the
  browser's centred text, so the rows set their own alignment.
*/
.ann-item {
  width: 100%;
  border-radius: 0;
  border-bottom: 1px solid var(--bd-1);
  background: none;
  cursor: pointer;
  text-align: left;
}

.ann-item:last-child {
  border-bottom: none;
}

.todo-item {
  width: 100%;
  border-radius: 6px;
  background: none;
  cursor: pointer;
  text-align: left;
}

.todo-group-head {
  background: var(--n-25);
  border-top: 1px solid var(--bd-1);
}

/*
  The announcement body is sanitised HTML (v-html), so its block elements arrive
  from the server rather than from this component -- white-space:pre-wrap would
  then double every newline between tags. Scoped styles do not reach v-html
  children, hence :deep().
*/
.ann-body {
  line-height: 1.85;
  color: var(--t-2);
}

.ann-body :deep(p) {
  margin: 0 0 var(--sp-2);
}

.ann-body :deep(p:last-child) {
  margin-bottom: 0;
}

.ann-body :deep(ul) {
  list-style: disc;
  padding-left: var(--sp-5);
  margin: 0 0 var(--sp-2);
}

.ann-body :deep(ol) {
  list-style: decimal;
  padding-left: var(--sp-5);
  margin: 0 0 var(--sp-2);
}

.ann-body :deep(blockquote) {
  border-left: 3px solid var(--bd-2);
  padding-left: var(--sp-3);
  color: var(--t-3);
  margin: 0 0 var(--sp-2);
}

.ann-body :deep(h1),
.ann-body :deep(h2),
.ann-body :deep(h3),
.ann-body :deep(h4) {
  margin: var(--sp-3) 0 var(--sp-2);
  font-weight: var(--fw-semi);
  color: var(--t-1);
}

.ann-body :deep(a) {
  color: var(--c-primary);
  text-decoration: underline;
}

/* NEW badge on an unread announcement; disappears once it has been opened. */
.new-chip {
  display: inline-block;
  margin-right: 5px;
  padding: 0 5px;
  border-radius: 3px;
  border: 1px solid var(--c-danger-border);
  background: var(--c-danger-soft);
  color: #B91C1C;
  font-size: var(--fs-11);
  font-weight: var(--fw-bold);
  letter-spacing: 0.03em;
  vertical-align: 1px;
}

.empty-todo {
  padding: var(--sp-5);
  text-align: center;
  color: var(--t-3);
  font-size: var(--fs-13);
}
</style>
