<script setup lang="ts">
import { computed } from 'vue'
import { useMetaStore } from '@/stores/meta'

/**
 * The three-level failure type cascade as a self-contained block.
 *
 * Narrowing as the user descends and clearing the levels below is what stops a
 * stale, now-inconsistent combination from being submitted -- the same rule the
 * server enforces, applied here for immediate feedback.
 *
 * The registration wizard's sample step keeps its own inline copy; this component
 * exists so new screens do not have to duplicate the logic again.
 */
export interface FailureTypeModel {
  failureTypeL1Code?: string | null
  failureTypeL2Code?: string | null
  failureTypeL3Code?: string | null
}

const props = withDefaults(
  defineProps<{
    model: FailureTypeModel
    labels?: [string, string, string]
  }>(),
  { labels: () => ['一级', '二级', '三级'] as [string, string, string] }
)

const meta = useMetaStore()
const level1Options = computed(() => meta.failureTypes)

function level2Options() {
  const l1 = meta.failureTypes.find((t) => t.code === props.model.failureTypeL1Code)
  return l1?.children ?? []
}

function level3Options() {
  const l2 = level2Options().find((t) => t.code === props.model.failureTypeL2Code)
  return l2?.children ?? []
}

function onLevel1Change() {
  props.model.failureTypeL2Code = null
  props.model.failureTypeL3Code = null
}

function onLevel2Change() {
  props.model.failureTypeL3Code = null
}
</script>

<template>
  <el-row :gutter="16">
    <el-col :span="8">
      <el-form-item :label="labels[0]">
        <el-select v-model="model.failureTypeL1Code" placeholder="请选择" clearable @change="onLevel1Change">
          <el-option v-for="t in level1Options" :key="t.code" :label="t.name" :value="t.code" />
        </el-select>
      </el-form-item>
    </el-col>
    <el-col :span="8">
      <el-form-item :label="labels[1]">
        <el-select
          v-model="model.failureTypeL2Code"
          placeholder="请先选择一级"
          :disabled="!model.failureTypeL1Code"
          clearable
          @change="onLevel2Change"
        >
          <el-option v-for="t in level2Options()" :key="t.code" :label="t.name" :value="t.code" />
        </el-select>
      </el-form-item>
    </el-col>
    <el-col :span="8">
      <el-form-item :label="labels[2]">
        <el-select
          v-model="model.failureTypeL3Code"
          placeholder="请先选择二级"
          :disabled="!model.failureTypeL2Code"
          clearable
        >
          <el-option v-for="t in level3Options()" :key="t.code" :label="t.name" :value="t.code" />
        </el-select>
      </el-form-item>
    </el-col>
  </el-row>
</template>
