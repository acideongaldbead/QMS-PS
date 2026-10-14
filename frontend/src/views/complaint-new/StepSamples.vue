<script setup lang="ts">
import type { CreateComplaintRequest } from '@/api/complaints'
import SampleFields from '@/components/SampleFields.vue'
import { emptySample } from './types'

const props = defineProps<{ form: CreateComplaintRequest }>()

function addSample() {
  props.form.samples.push(emptySample())
}

function removeSample(index: number) {
  props.form.samples.splice(index, 1)
}
</script>

<template>
  <div>
    <div class="row-between mb-3">
      <span class="fs-13 t-2">
        一个投诉可登记多个样品。样品可留空——样品到达后再补录也符合流程。
      </span>
      <el-button type="primary" plain @click="addSample">新增样品</el-button>
    </div>

    <el-empty v-if="form.samples.length === 0" description="尚未登记样品" />

    <el-card
      v-for="(sample, index) in form.samples"
      :key="index"
      class="sample-card"
      shadow="never"
    >
      <template #header>
        <div class="row-between">
          <span class="fw-semi">样品 {{ index + 1 }}</span>
          <el-button type="danger" link @click="removeSample(index)">移除</el-button>
        </div>
      </template>
      <SampleFields :model="sample" />
    </el-card>
  </div>
</template>

<style scoped>
.sample-card + .sample-card {
  margin-top: 12px;
}
.sample-card :deep(.el-card__header) {
  padding: 10px 16px;
  background: var(--n-25);
}
</style>
