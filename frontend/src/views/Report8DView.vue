<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { reportsApi, type ReportContent } from '@/api/reports'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'

/**
 * The 8D report itself: the D1-D8 sections assembled from the complaint's content,
 * laid out for reading and printing (requirement 3.9). Export is server-side Word.
 */
const props = defineProps<{ id: string; reportId: string }>()
const router = useRouter()
const auth = useAuthStore()

const content = ref<ReportContent | null>(null)
const loading = ref(false)
const exporting = ref(false)
const exportingPdf = ref(false)

const canExport = computed(() => auth.can('report:export'))
const canSend = computed(() => auth.can('report:send'))

async function load() {
  loading.value = true
  try {
    content.value = await reportsApi.view(props.reportId)
  } catch (e) {
    ElMessage.error('报告加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(load)

async function exportWord() {
  if (!content.value) return
  exporting.value = true
  try {
    await reportsApi.exportDocx(
      props.reportId,
      `8D_Report_${content.value.complaint.complaintId}_${content.value.report.versionNo}.docx`
    )
    ElMessage.success('已导出 Word')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    exporting.value = false
  }
}

/** The PDF is the read-only copy: circulate this one, edit the Word file. */
async function exportPdf() {
  if (!content.value) return
  exportingPdf.value = true
  try {
    await reportsApi.exportPdf(
      props.reportId,
      `8D_Report_${content.value.complaint.complaintId}_${content.value.report.versionNo}.pdf`
    )
    ElMessage.success('已导出 PDF')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    exportingPdf.value = false
  }
}

function goSend() {
  router.push(`/complaints/${props.id}/report/${props.reportId}/send`)
}

function nz(v?: string | null): string {
  return v || '—'
}

function date(v?: string | null): string {
  return v || '—'
}

function effectiveness(v?: boolean | null): string {
  if (v === true) return '有效'
  if (v === false) return '无效'
  return '未判定'
}
</script>

<template>
  <div v-loading="loading">
    <div class="page-head row-between no-print">
      <div class="row gap-3">
        <el-button link @click="router.push(`/complaints/${props.id}`)">返回投诉详情</el-button>
        <h1 style="margin: 0">{{ content?.report.reportId || props.reportId }}</h1>
        <el-tag v-if="content" size="small" type="info">{{ content.report.reportTypeName }}</el-tag>
      </div>
      <div class="row gap-2">
        <el-button v-if="canExport" @click="exportWord" :loading="exporting">导出 Word</el-button>
        <el-button v-if="canExport" @click="exportPdf" :loading="exportingPdf">导出 PDF</el-button>
        <el-button v-if="canSend" type="primary" @click="goSend">发送报告</el-button>
      </div>
    </div>

    <div v-if="content" class="report-sheet">
      <h2 class="rep-title">TECHNICAL REPORT / 8D Problem Report</h2>
      <p class="rep-sub">
        Nexperia Reference Number: {{ content.complaint.complaintId }}
        &nbsp;|&nbsp; 8D case nr: {{ content.report.reportId }}
        &nbsp;|&nbsp; Version: {{ content.report.versionNo }}
        &nbsp;|&nbsp; Template: {{ nz(content.report.templateCode) }}
      </p>
      <p class="rep-sub">
        Opened: {{ date(content.report.reportStartDate) }}
        &nbsp;|&nbsp; Closed: {{ date(content.report.reportCloseDate) }}
      </p>

      <h3>Complaint information</h3>
      <el-descriptions :column="3" border size="small">
        <el-descriptions-item label="Customer">{{ nz(content.complaint.labels?.customerName) }}</el-descriptions-item>
        <el-descriptions-item label="Product">{{ nz(content.complaint.labels?.productDescription) }}</el-descriptions-item>
        <el-descriptions-item label="Location of Failure">{{ nz(content.complaint.labels?.failureLocationName) }}</el-descriptions-item>
        <el-descriptions-item label="Start Date">{{ date(content.complaint.startDate) }}</el-descriptions-item>
        <el-descriptions-item label="Target Date">{{ date(content.complaint.targetDate) }}</el-descriptions-item>
        <el-descriptions-item label="Customer Ref. No.">{{ nz(content.complaint.customerReferenceId) }}</el-descriptions-item>
        <el-descriptions-item label="Customer contact">
          {{ nz(content.complaint.labels?.contactName) }}（{{ nz(content.complaint.labels?.contactEmail) }}）
        </el-descriptions-item>
        <el-descriptions-item label="Complaint Owner">{{ nz(content.complaint.labels?.ownerName) }}</el-descriptions-item>
        <el-descriptions-item label="Status">{{ nz(content.complaint.labels?.statusName) }}</el-descriptions-item>
      </el-descriptions>

      <h3>Customer failure description</h3>
      <p class="rep-text">
        {{ nz(content.complaint.failureDescription?.d0SymptomsDescription || content.complaint.failureDescription?.customerFailureDescription) }}
      </p>

      <h3>Detailed sample information</h3>
      <el-table :data="content.complaint.samples" size="small" border>
        <el-table-column label="Sample No." width="130">
          <template #default="{ row }">{{ row.sampleId }}</template>
        </el-table-column>
        <el-table-column label="Qty" width="90">
          <template #default="{ row }">{{ row.value.sampleQuantity }} {{ row.value.uom }}</template>
        </el-table-column>
        <el-table-column label="Reject Confirmed" width="140">
          <template #default="{ row }">{{ row.value.rejectConfirmed ? 'Yes' : 'No' }}</template>
        </el-table-column>
        <el-table-column label="Failure Type" width="140">
          <template #default="{ row }">{{ nz(row.value.failureTypeL3Code) }}</template>
        </el-table-column>
        <el-table-column label="Conclusion" min-width="200">
          <template #default="{ row }">{{ nz(row.value.conclusion) }}</template>
        </el-table-column>
      </el-table>

      <h3>D1 MULTIDISCIPLINARY team</h3>
      <el-table :data="content.team" size="small" border empty-text="未登记团队成员">
        <el-table-column prop="functionName" label="Function" width="200" />
        <el-table-column prop="memberName" label="Name" width="180" />
        <el-table-column prop="jobTitle" label="Job Title" />
      </el-table>

      <h3>D2 PROBLEM DESCRIPTION</h3>
      <p class="rep-text">
        {{ nz(content.complaint.failureDescription?.customerFailureDescription || content.complaint.failureDescription?.d0SymptomsDescription) }}
      </p>
      <p class="rep-text">
        有效性判定：{{ content.complaint.isValid === true ? '有效' : content.complaint.isValid === false ? '无效' : '未判定' }}
        <span v-if="content.complaint.failureDescription?.analysisConclusion">
          ；分析结论：{{ content.complaint.failureDescription.analysisConclusion }}
        </span>
      </p>

      <h3>D3 CONTAINMENT ACTIONS (Interim Actions)</h3>
      <p class="rep-text">
        是否需要遏制：{{ content.containment?.required === true ? '需要' : content.containment?.required === false ? '不需要' : '未判定' }}
        <span v-if="content.containment?.decisionNote">；理由：{{ content.containment.decisionNote }}</span>
      </p>
      <el-table :data="content.containment?.actions || []" size="small" border empty-text="未登记遏制措施">
        <el-table-column prop="plannedAction" label="Description" min-width="220" />
        <el-table-column label="Action owner" width="110">
          <template #default="{ row }">{{ nz(row.ownerName) }}</template>
        </el-table-column>
        <el-table-column label="Planned" width="110">
          <template #default="{ row }">{{ date(row.plannedCompletionDate) }}</template>
        </el-table-column>
        <el-table-column label="Completed" width="110">
          <template #default="{ row }">{{ date(row.completedDate) }}</template>
        </el-table-column>
        <el-table-column label="Status" width="100">
          <template #default="{ row }">{{ nz(row.statusName) }}</template>
        </el-table-column>
      </el-table>

      <h3>D4 ROOT CAUSE</h3>
      <div v-if="content.rootCauses.length" class="rep-text">
        <p v-for="rc in content.rootCauses" :key="rc.rootCauseId">
          • {{ rc.rootCauseDesc }}
          <span v-if="rc.riskAssessment">（风险评估：{{ rc.riskAssessment }}）</span>
          <span class="fs-12 t-3"> 3x5Why×{{ rc.whyVersionCount }}，鱼骨图×{{ rc.fishboneVersionCount }}</span>
        </p>
      </div>
      <p v-else class="rep-text t-3">尚未登记根因。</p>

      <h3>D5 / D6 CORRECTIVE ACTIONS</h3>
      <el-table :data="content.correctiveActions" size="small" border empty-text="尚未制定纠正措施">
        <el-table-column prop="correctiveActionId" label="No." width="140" />
        <el-table-column prop="plannedActionDesc" label="Actions" min-width="240" />
        <el-table-column label="Owner" width="100">
          <template #default="{ row }">{{ nz(row.ownerName) }}</template>
        </el-table-column>
        <el-table-column label="Target" width="110">
          <template #default="{ row }">{{ date(row.targetDate) }}</template>
        </el-table-column>
        <el-table-column label="Status" width="110">
          <template #default="{ row }">{{ nz(row.statusName) }}</template>
        </el-table-column>
        <el-table-column label="Verification" width="100">
          <template #default="{ row }">{{ effectiveness(row.isEffective) }}</template>
        </el-table-column>
      </el-table>

      <h3>D7 IMPLEMENTED SYSTEMIC CORRECTIVE ACTION</h3>
      <el-table :data="content.preventionFiles" size="small" border empty-text="尚未登记预防文件更新">
        <el-table-column label="Document" width="150">
          <template #default="{ row }">{{ nz(row.fileTypeName) }}</template>
        </el-table-column>
        <el-table-column label="Control program" min-width="160">
          <template #default="{ row }">{{ nz(row.controlProgram) }}</template>
        </el-table-column>
        <el-table-column label="Reference no." min-width="140">
          <template #default="{ row }">{{ nz(row.referenceNumber) }}</template>
        </el-table-column>
        <el-table-column label="Status" width="110">
          <template #default="{ row }">{{ nz(row.statusName) }}</template>
        </el-table-column>
      </el-table>

      <h3>Read-across</h3>
      <p class="rep-prompt">
        Analyze similar processes / systems / practices and implement the systemic
        corrective action where applicable.
      </p>

      <h3>D8 TEAM RECOGNITION</h3>
      <p class="rep-prompt">
        Date: {{ nz(content.report.reportCloseDate) }} · Recognize the collective
        efforts of the team.
      </p>

      <h3>SIGN-OFF AND DISTRIBUTION</h3>
      <el-descriptions :column="2" border size="small" class="mb-3">
        <el-descriptions-item label="Reported by">
          {{ nz(content.complaint.labels?.reportOwnerName) }}
        </el-descriptions-item>
        <el-descriptions-item label="Approved by">
          {{ nz(content.report.approval?.approverName) }}（{{ nz(content.report.approvalStatusName) }}）
        </el-descriptions-item>
      </el-descriptions>
      <el-table :data="content.distributions" size="small" border empty-text="尚未发送">
        <el-table-column label="Sent by" width="120">
          <template #default="{ row }">{{ nz(row.senderName) }}</template>
        </el-table-column>
        <el-table-column prop="recipient" label="Recipient" min-width="200" />
        <el-table-column prop="ccList" label="CC" min-width="160">
          <template #default="{ row }">{{ nz(row.ccList) }}</template>
        </el-table-column>
        <el-table-column prop="attachmentVersion" label="Version" width="100" />
      </el-table>
    </div>
  </div>
</template>

<style scoped>
.report-sheet {
  max-width: 920px;
  margin: 0 auto;
  padding: 24px 28px 48px;
  background: var(--bg-elevated, #fff);
  border: 1px solid var(--border-1, #e4e7ed);
  border-radius: var(--r-md, 6px);
}
.rep-title {
  text-align: center;
  font-size: 18px;
  margin: 0 0 4px;
}
.rep-sub {
  text-align: center;
  color: var(--t-3);
  font-size: var(--fs-12);
  margin: 0 0 4px;
}
/*
  The template's own prompt for the Read-across and Team Recognition blocks: the
  business confirmed (2026-10-14) that the system is not to fill them, so this is
  the intended presentation, not a placeholder awaiting data.
*/
.rep-prompt {
  margin: 0 0 10px;
  color: var(--t-3);
  font-size: var(--fs-12);
  line-height: 1.7;
}
.report-sheet h3 {
  margin: 22px 0 8px;
  font-size: 14px;
  font-weight: 600;
  color: var(--t-1, #303133);
  border-bottom: 1px solid var(--border-1, #e4e7ed);
  padding-bottom: 4px;
}
.rep-text {
  margin: 0 0 8px;
  line-height: 1.7;
  white-space: pre-wrap;
}
@media print {
  .report-sheet {
    max-width: none;
    border: none;
    padding: 0;
  }
}
</style>
