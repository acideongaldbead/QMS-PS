<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { reportsApi, type Approver, type ReportView } from '@/api/reports'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'
import RowAction from '@/components/RowAction.vue'

/**
 * D8: reports and settlement (requirement 3.9).
 *
 * This tab is the launcher: generate a report from the D1-D7 content, hand it to
 * an approver, and only once it is approved send it to the customer. The send is
 * deliberately the last step: it closes the complaint.
 */
const props = defineProps<{
  complaintId: string
  canGenerate: boolean
  canEdit: boolean
  canApprove: boolean
  canSend: boolean
}>()
const emit = defineEmits<{ (e: 'refresh'): void }>()
const router = useRouter()
const auth = useAuthStore()

const items = ref<ReportView[]>([])
const loading = ref(false)
const approvers = ref<Approver[]>([])

const dialogVisible = ref(false)
const generating = ref(false)
const form = reactive<{ reportType: string }>({ reportType: 'INTERIM' })

const submitVisible = ref(false)
const submitting = ref(false)
const submitTarget = ref<ReportView | null>(null)
const submitForm = reactive<{ approverId: string }>({ approverId: '' })

const approveVisible = ref(false)
const approving = ref(false)
const approveTarget = ref<ReportView | null>(null)
const approveForm = reactive<{ approved: boolean; comment: string }>({
  approved: true,
  comment: ''
})

const currentUserId = computed(() => auth.user?.employeeId ?? '')

async function refresh() {
  loading.value = true
  try {
    items.value = await reportsApi.list(props.complaintId)
  } catch (e) {
    ElMessage.error('报告列表加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(refresh)

function openGenerate() {
  form.reportType = 'INTERIM'
  dialogVisible.value = true
}

async function generate() {
  generating.value = true
  try {
    const created = await reportsApi.generate(props.complaintId, form.reportType)
    ElMessage.success('已生成报告：' + created.reportId)
    dialogVisible.value = false
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    generating.value = false
  }
}

/** A draft - or one that came back - can be handed over; an approved one cannot. */
function canSubmit(row: ReportView) {
  return props.canEdit && (row.approvalStatus === 'DRAFT' || row.approvalStatus === 'REJECTED')
}

/** Only the approver named on the pending task may decide. */
function canDecide(row: ReportView) {
  return (
    props.canApprove &&
    row.approvalStatus === 'PENDING' &&
    !!row.approval?.approverId &&
    row.approval.approverId === currentUserId.value
  )
}

async function openSubmit(row: ReportView) {
  submitTarget.value = row
  submitForm.approverId = ''
  submitVisible.value = true
  if (approvers.value.length === 0) {
    try {
      approvers.value = await reportsApi.approvers()
    } catch (e) {
      ElMessage.error('审批人列表加载失败：' + errorMessage(e))
    }
  }
}

async function submit() {
  if (!submitTarget.value || !submitForm.approverId) {
    ElMessage.warning('请选择审批人')
    return
  }
  submitting.value = true
  try {
    await reportsApi.submit(submitTarget.value.reportId, submitForm.approverId)
    ElMessage.success('已提交审批')
    submitVisible.value = false
    await refresh()
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    submitting.value = false
  }
}

function openApprove(row: ReportView) {
  approveTarget.value = row
  approveForm.approved = true
  approveForm.comment = ''
  approveVisible.value = true
}

async function decide() {
  if (!approveTarget.value) return
  if (!approveForm.approved && !approveForm.comment.trim()) {
    ElMessage.warning('驳回时必须填写审批意见')
    return
  }
  approving.value = true
  try {
    await reportsApi.approve(
      approveTarget.value.reportId,
      approveForm.approved,
      approveForm.comment.trim() || undefined
    )
    ElMessage.success(approveForm.approved ? '已批准' : '已驳回')
    approveVisible.value = false
    await refresh()
    emit('refresh')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    approving.value = false
  }
}

function openReport(row: ReportView) {
  router.push(`/complaints/${props.complaintId}/report/${row.reportId}`)
}

function openSend(row: ReportView) {
  router.push(`/complaints/${props.complaintId}/report/${row.reportId}/send`)
}

function approvalTagType(status: string): string {
  if (status === 'APPROVED') return 'success'
  if (status === 'REJECTED') return 'danger'
  if (status === 'PENDING') return 'warning'
  return 'info'
}

function formatTime(value?: string | null): string {
  return value ? String(value).replace('T', ' ').slice(0, 16) : '—'
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-12 t-3">
        系统按 XTE-0071 模板汇总 D1–D7 已录入内容生成 8D 报告；提交审批并批准后才能发送给客户（发送即结案）。
      </span>
      <el-button v-if="canGenerate" type="primary" plain @click="openGenerate">生成报告</el-button>
    </div>

    <el-table :data="items" v-loading="loading" size="small" empty-text="尚未生成 8D 报告">
      <el-table-column prop="reportId" label="报告ID" width="140" />
      <el-table-column label="类型" width="100">
        <template #default="{ row }">{{ row.reportTypeName || row.reportType }}</template>
      </el-table-column>
      <el-table-column prop="versionNo" label="版本" width="80" />
      <el-table-column label="审批状态" width="110">
        <template #default="{ row }">
          <el-tooltip
            v-if="row.approvalStatus === 'REJECTED' && row.approval?.comment"
            :content="'驳回意见：' + row.approval.comment"
            placement="top"
          >
            <el-tag size="small" type="danger">已驳回</el-tag>
          </el-tooltip>
          <el-tag v-else size="small" :type="approvalTagType(row.approvalStatus)">
            {{ row.approvalStatusName || row.approvalStatus }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="审批人" width="110">
        <template #default="{ row }">{{ row.approval?.approverName || '—' }}</template>
      </el-table-column>
      <el-table-column label="开始日期" width="110">
        <template #default="{ row }">{{ row.reportStartDate || '待发送' }}</template>
      </el-table-column>
      <el-table-column label="目标日期" width="110">
        <template #default="{ row }">{{ row.reportTargetDate || '待发送' }}</template>
      </el-table-column>
      <el-table-column label="关闭日期" width="110">
        <template #default="{ row }">{{ row.reportCloseDate || '待发送' }}</template>
      </el-table-column>
      <el-table-column label="生成时间" width="140">
        <template #default="{ row }">{{ formatTime(row.generatedAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <span class="row-acts">
            <RowAction act="viewReport" icon="file" label="查看报告" @click="openReport(row)" />
            <RowAction v-if="canSubmit(row)" act="submit" icon="upload" label="提交审批" @click="openSubmit(row)" />
            <RowAction v-if="canDecide(row)" act="approve" icon="check" tone="warning" label="审批" @click="openApprove(row)" />
            <RowAction
              v-if="canSend"
              act="send"
              icon="send"
              :disabled="row.approvalStatus !== 'APPROVED'"
              :label="row.approvalStatus === 'APPROVED' ? '发送' : '需先提交审批并获得批准'"
              @click="openSend(row)"
            />
          </span>
        </template>
      </el-table-column>
    </el-table>

    <!-- the rejection comment is the report owner's work list -->
    <el-alert
      v-for="row in items.filter((r) => r.approvalStatus === 'REJECTED' && r.approval?.comment)"
      :key="row.reportId"
      class="mt-3"
      type="warning"
      :closable="false"
      show-icon
      :title="`报告 ${row.reportId} 被驳回`"
      :description="'驳回意见：' + row.approval?.comment"
    />

    <el-card shadow="never" class="mt-4">
      <template #header>
        <span class="fw-semi">报告日期逻辑</span>
        <span class="fs-12 t-3" style="margin-left: 8px">需求 3.9 —— 日期由系统按规则自动填充</span>
      </template>
      <el-descriptions :column="3" border size="small">
        <el-descriptions-item label="开始日期">报告发送给客户的日期，自动填充且不可修改</el-descriptions-item>
        <el-descriptions-item label="目标日期">默认 = 开始日期 + 14 天</el-descriptions-item>
        <el-descriptions-item label="关闭日期">= 报告发送日（同开始日期），自动填充</el-descriptions-item>
      </el-descriptions>
    </el-card>

    <el-dialog v-model="dialogVisible" title="生成 8D 报告" width="520px" destroy-on-close>
      <el-form :model="form" label-width="100px">
        <el-form-item label="报告类型" required>
          <el-radio-group v-model="form.reportType">
            <el-radio value="INTERIM">中期报告</el-radio>
            <el-radio value="FINAL">终期报告</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <el-alert
        type="warning"
        :closable="false"
        show-icon
        title="生成前需 D6 措施全部验证通过、D7 文件更新全部完成。"
      />
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="generating" @click="generate">生成</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="submitVisible" title="提交审批" width="480px" destroy-on-close>
      <el-form :model="submitForm" label-width="90px">
        <el-form-item label="审批人" required>
          <el-select v-model="submitForm.approverId" placeholder="请选择审批人" style="width: 100%">
            <el-option
              v-for="person in approvers"
              :key="person.employeeId"
              :label="person.name"
              :value="person.employeeId"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <el-alert
        type="info"
        :closable="false"
        show-icon
        title="提交后报告进入审批中，只有被指定的审批人可以给出结论；批准后才能发送给客户。"
      />
      <template #footer>
        <el-button @click="submitVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="submit">提交</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="approveVisible" title="报告审批" width="520px" destroy-on-close>
      <el-form :model="approveForm" label-width="90px">
        <el-form-item label="审批结论" required>
          <el-radio-group v-model="approveForm.approved">
            <el-radio :value="true">批准</el-radio>
            <el-radio :value="false">驳回</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="审批意见" :required="!approveForm.approved">
          <el-input
            v-model="approveForm.comment"
            type="textarea"
            :rows="3"
            :placeholder="approveForm.approved ? '可选' : '驳回时必须说明原因，报告负责人据此修改'"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="approveVisible = false">取消</el-button>
        <el-button type="primary" :loading="approving" @click="decide">提交结论</el-button>
      </template>
    </el-dialog>
  </div>
</template>
