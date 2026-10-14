<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { complaintApi, type ComplaintDetail } from '@/api/complaints'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'
import { useMetaStore } from '@/stores/meta'
import AttachmentPanel from '@/components/AttachmentPanel.vue'
import ComplaintLogPanel from './complaint-detail/ComplaintLogPanel.vue'
import StageBar from './complaint-detail/StageBar.vue'
import SamplePanel from './complaint-detail/SamplePanel.vue'
import ShipmentPanel from './complaint-detail/ShipmentPanel.vue'
import VerificationPanel from './complaint-detail/VerificationPanel.vue'
import ContainmentPanel from './complaint-detail/ContainmentPanel.vue'
import RootCausePanel from './complaint-detail/RootCausePanel.vue'
import CorrectiveActionPanel from './complaint-detail/CorrectiveActionPanel.vue'
import ActionVerificationPanel from './complaint-detail/ActionVerificationPanel.vue'
import PreventionPanel from './complaint-detail/PreventionPanel.vue'
import ReportPanel from './complaint-detail/ReportPanel.vue'

const props = defineProps<{ id: string }>()
const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const meta = useMetaStore()

const detail = ref<ComplaintDetail | null>(null)
const loading = ref(false)

/**
 * Opens on the tab named by ?tab=, which is how the home page's to-do entries
 * jump straight to the work they are about. Unknown values fall back to the
 * registration tab.
 */
const TABS = ['d01', 'samples', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7', 'd8', 'files', 'logs']
const requestedTab = typeof route.query.tab === 'string' ? route.query.tab : ''
const activeTab = ref(TABS.includes(requestedTab) ? requestedTab : 'd01')

const canEditComplaint = computed(() => auth.can('complaint:edit'))
const canEditSamples = computed(() => auth.can('sample:edit') || auth.can('complaint:edit'))

async function load() {
  loading.value = true
  try {
    detail.value = await complaintApi.detail(props.id)
  } catch (e) {
    ElMessage.error('投诉详情加载失败：' + errorMessage(e))
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await meta.ensureLoaded()
  await load()
})

function isOverdue(): boolean {
  return !!detail.value && detail.value.overdueDays > 0 && !detail.value.closeDate
}

/** Resolves the close reason code to its dictionary name for display. */
const closeReasonName = computed(() => {
  const code = detail.value?.closeReasonCode
  if (!code) return null
  return meta.closeReasons.find((r) => r.code === code)?.nameCn ?? code
})
</script>

<template>
  <div v-loading="loading">
    <div class="page-head">
      <div class="row-between">
        <div class="row gap-3">
          <h1>{{ props.id }}</h1>
          <el-tag v-if="detail?.closeDate" type="success" size="small">已结案</el-tag>
          <el-tag v-else-if="isOverdue()" type="danger" size="small">超期 {{ detail?.overdueDays }} 天</el-tag>
          <el-tag v-else type="info" size="small">{{ detail?.labels?.statusName }}</el-tag>
        </div>
        <el-button link @click="router.push('/complaints')">返回汇总</el-button>
      </div>
    </div>

    <template v-if="detail">
      <el-card shadow="never" class="mb-4">
        <StageBar
          :current-stage="detail.currentStage"
          :overdue-days="detail.overdueDays"
          :closed="!!detail.closeDate"
        />
        <el-descriptions :column="4" border size="small" class="mt-4">
          <el-descriptions-item label="质量合作伙伴">{{ detail.labels?.customerName }}</el-descriptions-item>
          <el-descriptions-item label="产品">{{ detail.labels?.productDescription || detail.product?.materialCode || '—' }}</el-descriptions-item>
          <el-descriptions-item label="投诉类型">{{ detail.labels?.complaintTypeName }}</el-descriptions-item>
          <el-descriptions-item label="优先级">{{ detail.labels?.priorityName }}</el-descriptions-item>
          <el-descriptions-item label="开始日期">{{ detail.startDate }}</el-descriptions-item>
          <el-descriptions-item label="目标日期">
            <span :class="{ 't-danger': isOverdue() }">{{ detail.targetDate }}</span>
          </el-descriptions-item>
          <el-descriptions-item label="客户要求日期">{{ detail.customerTargetDate }}</el-descriptions-item>
          <el-descriptions-item label="关闭日期">{{ detail.closeDate || '—' }}</el-descriptions-item>
          <el-descriptions-item label="投诉负责人">{{ detail.labels?.ownerName }}</el-descriptions-item>
          <el-descriptions-item label="协调人">{{ detail.labels?.coordinatorName }}</el-descriptions-item>
          <el-descriptions-item label="验证负责人">{{ detail.labels?.verificationOwnerName || '—' }}</el-descriptions-item>
          <el-descriptions-item label="报告负责人">{{ detail.labels?.reportOwnerName || '—' }}</el-descriptions-item>
        </el-descriptions>
      </el-card>

      <el-tabs v-model="activeTab" type="border-card">
        <el-tab-pane label="登记信息" name="d01">
          <el-descriptions :column="3" border size="small">
            <el-descriptions-item label="失效位置">{{ detail.labels?.failureLocationName }}</el-descriptions-item>
            <el-descriptions-item label="子分部">{{ detail.labels?.subSegmentName }}</el-descriptions-item>
            <el-descriptions-item label="收货/售达方">{{ detail.labels?.shipToName || '—' }}</el-descriptions-item>
            <el-descriptions-item label="联系人">{{ detail.labels?.contactName }}</el-descriptions-item>
            <el-descriptions-item label="联系人邮箱">{{ detail.labels?.contactEmail || '—' }}</el-descriptions-item>
            <el-descriptions-item label="是否应用">{{ detail.qualityPartner?.application }}</el-descriptions-item>
            <el-descriptions-item label="客户失效模式">{{ detail.labels?.customerFailureModeName }}</el-descriptions-item>
            <el-descriptions-item label="失效数量">
              {{ detail.failureDescription?.quantityFailing ?? '—' }} {{ detail.failureDescription?.quantityFailingUom || '' }}
            </el-descriptions-item>
            <el-descriptions-item label="退回数量">
              {{ detail.failureDescription?.qualityReturned ?? '—' }} {{ detail.failureDescription?.qualityReturnedUom || '' }}
            </el-descriptions-item>
            <el-descriptions-item label="客户参考 ID">{{ detail.customerReferenceId || '—' }}</el-descriptions-item>
            <el-descriptions-item label="客户采购订单">{{ detail.failureDescription?.customerPo || '—' }}</el-descriptions-item>
            <el-descriptions-item label="销售订单">{{ detail.failureDescription?.salesOrder || '—' }}</el-descriptions-item>
            <el-descriptions-item label="客户失效描述" :span="3">
              {{ detail.failureDescription?.customerFailureDescription || '—' }}
            </el-descriptions-item>
            <el-descriptions-item label="D0 症状描述" :span="3">
              {{ detail.failureDescription?.d0SymptomsDescription || '—' }}
            </el-descriptions-item>
            <el-descriptions-item label="发起人" :span="1">
              {{ detail.labels?.createdByName || detail.createdBy }}
            </el-descriptions-item>
            <el-descriptions-item label="登记时间" :span="2">
              {{ detail.createdAt ? String(detail.createdAt).replace('T', ' ').slice(0, 19) : '—' }}
            </el-descriptions-item>
          </el-descriptions>
        </el-tab-pane>

        <el-tab-pane label="样品与物流" name="samples">
          <el-card shadow="never" class="mb-4">
            <template #header><span class="fw-semi">客诉样品</span></template>
            <SamplePanel
              :complaint-id="detail.complaintId"
              :samples="detail.samples"
              :can-edit="canEditSamples"
              @refresh="load"
            />
          </el-card>
          <el-card shadow="never">
            <template #header><span class="fw-semi">物流批次</span></template>
            <ShipmentPanel :complaint-id="detail.complaintId" :can-edit="canEditSamples" />
          </el-card>
        </el-tab-pane>

        <el-tab-pane label="D2 验证与问题定义" name="d2">
          <VerificationPanel
            :complaint-id="detail.complaintId"
            :is-valid="detail.isValid ?? null"
            :close-date="detail.closeDate"
            :close-reason-name="closeReasonName"
            :samples="detail.samples"
            :can-verify="auth.can('verify:edit')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D3 遏制措施" name="d3">
          <ContainmentPanel
            :complaint-id="detail.complaintId"
            :can-edit="auth.can('containment:edit')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D4 根因分析" name="d4">
          <RootCausePanel
            :complaint-id="detail.complaintId"
            :can-edit="auth.can('rootcause:edit')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D5 纠正措施" name="d5">
          <CorrectiveActionPanel
            :complaint-id="detail.complaintId"
            :can-edit="auth.can('action:edit')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D6 措施实施与验证" name="d6">
          <ActionVerificationPanel
            :complaint-id="detail.complaintId"
            :can-verify="auth.can('action:verify')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D7 预防再发生" name="d7">
          <PreventionPanel
            :complaint-id="detail.complaintId"
            :can-edit="auth.can('prevention:edit')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="D8 报告与结案" name="d8">
          <ReportPanel
            :complaint-id="detail.complaintId"
            :can-generate="auth.can('report:generate')"
            :can-edit="auth.can('report:edit')"
            :can-approve="auth.can('report:approve')"
            :can-send="auth.can('report:send')"
            @refresh="load"
          />
        </el-tab-pane>

        <el-tab-pane label="附件" name="files">
          <AttachmentPanel
            biz-type="Complaint"
            :biz-id="detail.complaintId"
            :readonly="!canEditComplaint"
          />
        </el-tab-pane>

        <el-tab-pane label="沟通与流程日志" name="logs">
          <ComplaintLogPanel :complaint-id="detail.complaintId" />
        </el-tab-pane>
      </el-tabs>
    </template>
  </div>
</template>
