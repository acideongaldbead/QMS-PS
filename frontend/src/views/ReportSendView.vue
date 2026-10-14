<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { reportsApi, type ReportContent, type ReportSendRequest } from '@/api/reports'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'

/**
 * Sending the 8D report to the customer (requirement 3.9).
 *
 * Only Sales Quality may send (the route already enforces report:send). The sender
 * is the signed-in user and cannot be changed; the recipient defaults to the
 * complaint's customer contact. Sending writes the communication log and closes
 * the complaint on the send day.
 */
const props = defineProps<{ id: string; reportId: string }>()
const router = useRouter()
const auth = useAuthStore()

const content = ref<ReportContent | null>(null)
const loading = ref(false)
const sending = ref(false)

const recipients = ref<string[]>([])
const ccs = ref<string[]>([])
const subject = ref('')
const body = ref('')

const senderName = computed(() => auth.user?.name || '')
const senderEmail = computed(() => auth.user?.email || '')

function emailOf(label?: string | null, email?: string | null): string {
  if (email && label) return `${label} <${email}>`
  return email || label || ''
}

async function load() {
  loading.value = true
  try {
    const data = await reportsApi.view(props.reportId)
    content.value = data
    const c = data.complaint
    const contact = emailOf(c.labels?.contactName, c.labels?.contactEmail)
    recipients.value = contact ? [contact] : []
    ccs.value = []
    subject.value = `【${data.report.reportTypeName}】${c.complaintId} - Technical Report ${data.report.versionNo}`
    body.value =
      `Dear ${c.labels?.contactName || 'Customer'},\n\n` +
      `关于贵司反馈的质量问题（客户参考号 ${c.customerReferenceId || '—'}），` +
      `随函附上我方 8D 问题解决报告（${data.report.reportTypeName} ${data.report.versionNo}）。\n\n` +
      `Best regards,\n${senderName.value}`
  } catch (e) {
    ElMessage.error('报告加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(load)

const approved = computed(() => content.value?.report.approvalStatus === 'APPROVED')

const checks = computed(() => [
  { label: '收件人至少一人', ok: recipients.value.length > 0 },
  { label: '邮件主题不为空', ok: subject.value.trim().length > 0 },
  { label: '邮件正文不为空', ok: body.value.trim().length > 0 },
  { label: '报告已生成', ok: !!content.value },
  // The server refuses an unapproved send; showing it here tells the reader
  // before they fill the form instead of through a 409 at the end.
  { label: '报告已通过审批', ok: approved.value }
])
const allOk = computed(() => checks.value.every((c) => c.ok))

async function confirmSend() {
  if (!content.value || !allOk.value) return
  try {
    await ElMessageBox.confirm(
      `发送后将自动生成沟通日志，且不可撤回；投诉单将按发送日结案。\n\n收件人：${recipients.value.join('; ')}`,
      '确认发送 8D 报告',
      { type: 'warning', confirmButtonText: '确认发送', cancelButtonText: '取消' }
    )
  } catch {
    return
  }
  sending.value = true
  try {
    const payload: ReportSendRequest = {
      recipient: recipients.value.join(';'),
      ccList: ccs.value.length ? ccs.value.join(';') : null,
      subject: subject.value.trim(),
      body: body.value
    }
    const result = await reportsApi.send(props.reportId, payload)
    ElMessage.success(
      `报告已发送给客户；开始日期与关闭日期已自动填充为 ${result.report.reportStartDate}，投诉单已结案。`
    )
    await load()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    sending.value = false
  }
}

function formatTime(value?: string | null): string {
  return value ? String(value).replace('T', ' ').slice(0, 16) : '—'
}

function nz(v?: string | null): string {
  return v || '—'
}
</script>

<template>
  <div v-loading="loading">
    <div class="page-head row-between no-print">
      <div class="row gap-3">
        <el-button link @click="router.push(`/complaints/${props.id}/report/${props.reportId}`)">
          返回报告
        </el-button>
        <h1 style="margin: 0">发送 8D 报告给客户</h1>
      </div>
      <el-button type="primary" :loading="sending" :disabled="!allOk" @click="confirmSend">
        发送报告
      </el-button>
    </div>

    <el-alert
      v-if="content && !approved"
      class="mb-3"
      type="warning"
      :closable="false"
      show-icon
      title="该报告尚未通过审批，不能发送给客户"
      :description="`当前审批状态：${content.report.approvalStatusName || content.report.approvalStatus}。请在 D8 页签提交审批，并由审批人批准后再发送。`"
    />

    <div v-if="content" class="send-grid">
      <el-card shadow="never">
        <template #header><span class="fw-semi">收件人与抄送</span></template>
        <el-form label-width="90px">
          <el-form-item label="发件人">
            <el-input :model-value="`${senderName}（${senderEmail}）`" disabled />
            <el-tag size="small" type="success" style="margin-left: 8px">Sales Quality 专属</el-tag>
          </el-form-item>
          <el-form-item label="收件人" required>
            <el-select
              v-model="recipients"
              multiple
              filterable
              allow-create
              default-first-option
              placeholder="自动带出客户联系人，可调整"
              style="width: 100%"
            />
          </el-form-item>
          <el-form-item label="抄送">
            <el-select
              v-model="ccs"
              multiple
              filterable
              allow-create
              default-first-option
              placeholder="支持添加多个抄送人"
              style="width: 100%"
            />
          </el-form-item>
          <el-form-item label="邮件主题" required>
            <el-input v-model="subject" />
          </el-form-item>
          <el-form-item label="邮件正文" required>
            <el-input v-model="body" type="textarea" :rows="8" resize="none" />
          </el-form-item>
        </el-form>
      </el-card>

      <div>
        <el-card shadow="never" class="mb-4">
          <template #header><span class="fw-semi">发送前校验</span></template>
          <ul class="check-list">
            <li v-for="c in checks" :key="c.label">
              <span :class="c.ok ? 'ok' : 'bad'">{{ c.ok ? '✓' : '✗' }}</span>
              {{ c.label }}
            </li>
          </ul>
        </el-card>

        <el-card shadow="never" class="mb-4">
          <template #header><span class="fw-semi">发送规则</span></template>
          <el-descriptions :column="1" size="small" border>
            <el-descriptions-item label="发送权限">仅 Sales Quality 角色（需求 3.9）</el-descriptions-item>
            <el-descriptions-item label="发件人">自动为当前 Sales Quality 用户</el-descriptions-item>
            <el-descriptions-item label="收件人">自动带出客户联系人，可手工调整</el-descriptions-item>
            <el-descriptions-item label="沟通日志">发送后自动生成，不可修改或删除</el-descriptions-item>
            <el-descriptions-item label="日期">开始日期 = 关闭日期 = 发送日；目标日期 = 开始 + 14 天</el-descriptions-item>
          </el-descriptions>
        </el-card>

        <el-card shadow="never">
          <template #header><span class="fw-semi">历史沟通记录（{{ content.distributions.length }}）</span></template>
          <el-table :data="content.distributions" size="small" empty-text="尚未发送">
            <el-table-column label="发送时间" width="150">
              <template #default="{ row }">{{ formatTime(row.sentAt) }}</template>
            </el-table-column>
            <el-table-column label="发件人" width="100">
              <template #default="{ row }">{{ nz(row.senderName) }}</template>
            </el-table-column>
            <el-table-column prop="recipient" label="收件人" min-width="180" show-overflow-tooltip />
            <el-table-column label="版本" width="90">
              <template #default="{ row }">{{ nz(row.attachmentVersion) }}</template>
            </el-table-column>
          </el-table>
        </el-card>
      </div>
    </div>
  </div>
</template>

<style scoped>
.send-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
  gap: var(--sp-4, 16px);
  align-items: start;
}
.check-list {
  margin: 0;
  padding-left: 0;
  list-style: none;
}
.check-list li {
  padding: 4px 0;
  font-size: var(--fs-13, 13px);
}
.check-list .ok {
  color: var(--c-success, #67c23a);
  font-weight: 600;
  margin-right: 6px;
}
.check-list .bad {
  color: var(--c-danger, #f56c6c);
  font-weight: 600;
  margin-right: 6px;
}
@media (max-width: 1100px) {
  .send-grid {
    grid-template-columns: 1fr;
  }
}
</style>
