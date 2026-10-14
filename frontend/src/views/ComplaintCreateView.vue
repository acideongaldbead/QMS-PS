<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { complaintApi, type ComplaintDetail, type CreatedComplaint } from '@/api/complaints'
import { errorMessage } from '@/api/http'
import { useMetaStore } from '@/stores/meta'
import AttachmentPanel from '@/components/AttachmentPanel.vue'
import StepHeader from './complaint-new/StepHeader.vue'
import StepQualityPartner from './complaint-new/StepQualityPartner.vue'
import StepProduct from './complaint-new/StepProduct.vue'
import StepFailureDescription from './complaint-new/StepFailureDescription.vue'
import StepSamples from './complaint-new/StepSamples.vue'
import { emptyComplaintForm, STEP_TITLES } from './complaint-new/types'

const route = useRoute()
const router = useRouter()
const meta = useMetaStore()

const step = ref(0)
const form = reactive(emptyComplaintForm())
const submitting = ref(false)
const serverError = ref('')
const created = ref<CreatedComplaint | null>(null)
const savedDetail = ref<ComplaintDetail | null>(null)
/** Set when the form was filled from a historical complaint (the ledger's 复制). */
const copiedFrom = ref('')

/**
 * Copying a complaint carries the reusable content over - customer, product,
 * responsible people, failure description - and leaves behind everything the
 * flow owns: the id, the three dates and the customer reference are regenerated
 * on submit, and the previous complaint's analysis results do not travel with it.
 */
async function prefillFrom(sourceId: string) {
  try {
    const detail = await complaintApi.detail(sourceId)
    Object.assign(form.header, detail.header, {
      startDate: null,
      targetDate: null,
      customerReferenceId: null
    })
    if (detail.qualityPartner) Object.assign(form.qualityPartner, detail.qualityPartner)
    if (detail.product) Object.assign(form.product, detail.product)
    if (detail.failureDescription) {
      Object.assign(form.failureDescription, detail.failureDescription, {
        analysisConclusion: null
      })
    }
    form.samples = (detail.samples ?? []).map((sample) => ({ ...sample.value, conclusion: null }))
    copiedFrom.value = sourceId
  } catch (e) {
    ElMessage.error('复制来源加载失败：' + errorMessage(e))
  }
}

onMounted(async () => {
  try {
    await meta.ensureLoaded()
  } catch (e) {
    ElMessage.error('主数据加载失败：' + errorMessage(e))
  }
  const source = route.query.copyFrom
  if (typeof source === 'string' && source) {
    await prefillFrom(source)
  }
})

/**
 * Mirrors the server's required-field rules so the user is told on the step that
 * is wrong instead of at the end. The server remains the authority: anything it
 * rejects is shown verbatim after submit.
 */
function stepMissing(index: number): string[] {
  const missing: string[] = []
  if (index === 0) {
    if (!form.header.complaintTypeCode) missing.push('投诉类型')
    if (!form.header.priorityCode) missing.push('优先级')
    if (!form.header.failureLocationCode) missing.push('失效位置')
    if (!form.header.complaintOwnerId) missing.push('投诉负责人')
    if (!form.header.coordinatorId) missing.push('协调人')
    if (!form.header.customerTargetDate) missing.push('客户要求目标日期')
  }
  if (index === 1) {
    if (!form.qualityPartner.qualityPartnerCode) missing.push('质量合作伙伴')
    if (!form.qualityPartner.application) missing.push('应用')
    if (!form.qualityPartner.contactPersonId) missing.push('联系人')
    if (!form.qualityPartner.subSegmentCode) missing.push('子分部')
  }
  if (index === 2) {
    if (!form.product.productTypeCode) missing.push('产品类型')
    if (!form.product.packingTypeCode) missing.push('包装类型')
  }
  if (index === 3) {
    if (!form.failureDescription.customerFailureModeCode) missing.push('客户失效模式')
  }
  return missing
}

const currentStepMissing = computed(() => stepMissing(step.value))

const allMissing = computed(() => {
  const all: string[] = []
  for (let i = 0; i < 4; i++) all.push(...stepMissing(i))
  return all
})

function next() {
  const missing = currentStepMissing.value
  if (missing.length > 0) {
    ElMessage.warning('请先填写：' + missing.join('、'))
    return
  }
  if (step.value < STEP_TITLES.length - 1) step.value += 1
}

function prev() {
  if (step.value > 0) step.value -= 1
}

async function submit() {
  serverError.value = ''
  if (allMissing.value.length > 0) {
    ElMessage.warning('请先填写：' + allMissing.value.join('、'))
    return
  }
  submitting.value = true
  try {
    created.value = await complaintApi.create(JSON.parse(JSON.stringify(form)))
    savedDetail.value = await complaintApi.detail(created.value.complaintId)
    ElMessage.success('登记成功：' + created.value.complaintId)
  } catch (e) {
    serverError.value = errorMessage(e)
  } finally {
    submitting.value = false
  }
}

function registerAnother() {
  Object.assign(form, emptyComplaintForm())
  created.value = null
  savedDetail.value = null
  serverError.value = ''
  copiedFrom.value = ''
  step.value = 0
}

function openDetail() {
  if (created.value) router.push(`/complaints/${created.value.complaintId}`)
}
</script>

<template>
  <div>
    <div class="page-head">
      <div class="row-between">
        <h1>登记投诉</h1>
        <el-button link @click="router.push('/complaints')">返回汇总</el-button>
      </div>
    </div>

    <el-alert
      v-if="copiedFrom && !created"
      class="mb-3"
      type="info"
      :closable="false"
      show-icon
      title="已按历史投诉预填"
      :description="`来源 ${copiedFrom}：携带客户、产品、责任人与失效描述；投诉ID 与开始/目标/关闭日期将在提交时重新生成。`"
    />

    <!-- Result panel: shown once the complaint is stored -->
    <template v-if="created && savedDetail">
      <el-result icon="success" :title="'登记成功 ' + created.complaintId">
        <template #sub-title>
          <span>阶段 {{ created.currentStage }}　状态 {{ savedDetail.labels?.statusName || created.statusCode }}</span>
        </template>
        <template #extra>
          <el-button type="primary" @click="openDetail">查看详情</el-button>
          <el-button @click="registerAnother">再登记一张</el-button>
          <el-button link @click="router.push('/complaints')">返回汇总</el-button>
        </template>
      </el-result>

      <el-descriptions :column="3" border class="mt-4">
        <el-descriptions-item label="投诉ID">{{ created.complaintId }}</el-descriptions-item>
        <el-descriptions-item label="开始日期">{{ created.startDate }}</el-descriptions-item>
        <el-descriptions-item label="目标日期">{{ created.targetDate }}</el-descriptions-item>
        <el-descriptions-item label="客户要求日期">{{ created.customerTargetDate }}</el-descriptions-item>
        <el-descriptions-item label="投诉类型">{{ savedDetail.labels?.complaintTypeName }}</el-descriptions-item>
        <el-descriptions-item label="优先级">{{ savedDetail.labels?.priorityName }}</el-descriptions-item>
        <el-descriptions-item label="质量合作伙伴">{{ savedDetail.labels?.customerName }}</el-descriptions-item>
        <el-descriptions-item label="联系人">{{ savedDetail.labels?.contactName }}</el-descriptions-item>
        <el-descriptions-item label="收货/售达方">{{ savedDetail.labels?.shipToName || '—' }}</el-descriptions-item>
        <el-descriptions-item label="产品">{{ savedDetail.labels?.productDescription || savedDetail.product?.materialCode || '—' }}</el-descriptions-item>
        <el-descriptions-item label="投诉负责人">{{ savedDetail.labels?.ownerName }}</el-descriptions-item>
        <el-descriptions-item label="协调人">{{ savedDetail.labels?.coordinatorName }}</el-descriptions-item>
        <el-descriptions-item label="样品数量">{{ created.sampleIds.length }}</el-descriptions-item>
        <el-descriptions-item label="发起人">
          {{ savedDetail.labels?.createdByName || savedDetail.createdBy }}
        </el-descriptions-item>
        <el-descriptions-item label="失效模式">{{ savedDetail.labels?.customerFailureModeName }}</el-descriptions-item>
      </el-descriptions>

      <el-card shadow="never" class="mt-4">
        <template #header>
          <span class="fw-semi">附件</span>
          <span class="fs-12 t-3" style="margin-left: 8px">
            登记后即可上传，失效描述、分析图片、客户邮件都挂在这里
          </span>
        </template>
        <AttachmentPanel biz-type="Complaint" :biz-id="created.complaintId" />
      </el-card>
    </template>

    <!-- Wizard -->
    <template v-else>
      <el-steps :active="step" finish-status="success" align-center class="mb-5">
        <el-step v-for="(title, i) in STEP_TITLES" :key="title" :title="title" :description="`第 ${i + 1} 步`" />
      </el-steps>

      <el-alert
        v-if="serverError"
        class="mb-4"
        type="error"
        :closable="false"
        show-icon
        title="提交未通过校验"
        :description="serverError"
      />

      <el-card shadow="never">
        <el-form label-width="150px" label-position="right">
          <StepHeader v-if="step === 0" :form="form" />
          <StepQualityPartner v-else-if="step === 1" :form="form" />
          <StepProduct v-else-if="step === 2" :form="form" />
          <StepFailureDescription v-else-if="step === 3" :form="form" />
          <StepSamples v-else :form="form" />
        </el-form>
      </el-card>

      <div class="wizard-actions">
        <el-button :disabled="step === 0" @click="prev">上一步</el-button>
        <span class="fs-12 t-3">
          {{ currentStepMissing.length === 0 ? '本步已填写完整' : '待填写：' + currentStepMissing.join('、') }}
        </span>
        <el-button v-if="step < STEP_TITLES.length - 1" type="primary" @click="next">下一步</el-button>
        <el-button v-else type="primary" :loading="submitting" @click="submit">提交登记</el-button>
      </div>
    </template>
  </div>
</template>

<style scoped>
.wizard-actions {
  display: flex;
  align-items: center;
  gap: 16px;
  justify-content: flex-end;
  margin-top: 16px;
}
.wizard-actions span {
  margin-right: auto;
}
</style>
