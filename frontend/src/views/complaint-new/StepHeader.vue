<script setup lang="ts">
import { computed } from 'vue'
import { useMetaStore } from '@/stores/meta'
import type { CreateComplaintRequest } from '@/api/complaints'

/**
 * The form model is a single reactive object owned by the wizard; each step
 * receives it and edits its own slice. That keeps one source of truth across the
 * five steps instead of five copies to merge on submit.
 */
const props = defineProps<{ form: CreateComplaintRequest }>()
const meta = useMetaStore()

function isoToday(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T00:00:00`)
  d.setDate(d.getDate() + days)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

/** Requirement 3.1.2: start date defaults to the creation date plus 7 days. */
const effectiveStartDate = computed(
  () => props.form.header.startDate || addDays(isoToday(), 7)
)

/** Target date = start date + the priority's configured days. */
const effectiveTargetDate = computed(() => {
  if (props.form.header.targetDate) return props.form.header.targetDate
  const days = meta.priorityDays[props.form.header.priorityCode]
  if (days === undefined) return ''
  return addDays(effectiveStartDate.value, days)
})

const priorityDaysHint = computed(() => {
  const days = meta.priorityDays[props.form.header.priorityCode]
  return days === undefined ? '' : `开始日期 + ${days} 天`
})

/**
 * Requirement 3.1.2: warn when the system target date would land after the date
 * the customer asked for. This is a warning, not a rule, so it never blocks save.
 */
const customerDateWarning = computed(() => {
  const customer = props.form.header.customerTargetDate
  const target = effectiveTargetDate.value
  if (!customer || !target) return ''
  return customer < target
    ? `客户要求完成日期（${customer}）早于系统目标日期（${target}），请评估是否需要提升优先级。`
    : ''
})
</script>

<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="投诉类型" required>
          <el-select v-model="form.header.complaintTypeCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.complaintTypes"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="优先级" required>
          <el-select v-model="form.header.priorityCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.priorities"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="失效位置" required>
          <el-select v-model="form.header.failureLocationCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.failureLocations"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="投诉负责人" required>
          <el-select v-model="form.header.complaintOwnerId" placeholder="请选择" clearable filterable>
            <el-option
              v-for="e in meta.employees"
              :key="e.id"
              :label="e.name"
              :value="e.id"
            >
              <span>{{ e.name }}</span>
              <span class="option-sub">{{ e.jobTitle || e.id }}</span>
            </el-option>
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="协调人" required>
          <el-select v-model="form.header.coordinatorId" placeholder="请选择" clearable filterable>
            <el-option
              v-for="e in meta.employees"
              :key="e.id"
              :label="e.name"
              :value="e.id"
            >
              <span>{{ e.name }}</span>
              <span class="option-sub">{{ e.jobTitle || e.id }}</span>
            </el-option>
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="验证负责人">
          <el-select v-model="form.header.verificationOwnerId" placeholder="请选择" clearable filterable>
            <el-option
              v-for="e in meta.employees"
              :key="e.id"
              :label="e.name"
              :value="e.id"
            >
              <span>{{ e.name }}</span>
              <span class="option-sub">{{ e.jobTitle || e.id }}</span>
            </el-option>
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="报告负责人">
          <el-select v-model="form.header.reportOwnerId" placeholder="请选择" clearable filterable>
            <el-option
              v-for="e in meta.employees"
              :key="e.id"
              :label="e.name"
              :value="e.id"
            >
              <span>{{ e.name }}</span>
              <span class="option-sub">{{ e.jobTitle || e.id }}</span>
            </el-option>
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="客户要求目标日期" required>
          <el-date-picker
            v-model="form.header.customerTargetDate"
            type="date"
            value-format="YYYY-MM-DD"
            placeholder="客户要求的完成日期"
          />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="开始日期">
          <el-date-picker
            v-model="form.header.startDate"
            type="date"
            value-format="YYYY-MM-DD"
            placeholder="留空则按创建日期 + 7 天"
          />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="目标日期">
          <el-date-picker
            v-model="form.header.targetDate"
            type="date"
            value-format="YYYY-MM-DD"
            :placeholder="'留空则 ' + (priorityDaysHint || '按优先级自动计算')"
          />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="客户参考 ID">
          <el-input v-model="form.header.customerReferenceId" placeholder="客户侧参考编号" />
        </el-form-item>
      </el-col>
    </el-row>

    <div class="date-preview">
      <span class="fs-12 t-3">日期预览：</span>
      <span class="fs-12">开始 {{ effectiveStartDate || '—' }}</span>
      <span class="fs-12 t-3">／</span>
      <span class="fs-12">目标 {{ effectiveTargetDate || '（需先选优先级）' }}</span>
      <span v-if="priorityDaysHint" class="fs-12 t-4">（{{ priorityDaysHint }}）</span>
    </div>

    <el-alert
      v-if="customerDateWarning"
      class="mt-3"
      type="warning"
      :closable="false"
      show-icon
      :title="customerDateWarning"
    />
  </div>
</template>

<style scoped>
.date-preview {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: var(--bg-sunken);
  border-radius: var(--r-2);
}

/* The collapsed select shows only the name, so it never truncates; the job title
   stays readable inside the dropdown. */
.option-sub {
  float: right;
  margin-left: 16px;
  color: var(--t-4);
  font-size: var(--fs-12);
}
</style>
