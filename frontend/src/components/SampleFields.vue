<script setup lang="ts">
import { computed } from 'vue'
import { useMetaStore } from '@/stores/meta'
import type { SampleForm } from '@/api/complaints'

/**
 * The sample fields including the three-level failure type cascade, shared by the
 * registration wizard and the edit dialog on the detail page.
 *
 * Layout: a uniform 4-column grid for the short fields, then the two free-text
 * fields side by side at matching width, then the cascade on its own row. Keeping
 * every short field at the same width is what makes the block read as aligned.
 *
 * The cascade narrows as the user descends and clears the levels below, so a
 * stale, now-inconsistent combination can never be submitted.
 */
const props = defineProps<{ model: SampleForm }>()
const meta = useMetaStore()

const UOMS = ['PCS', 'SET', 'KG', 'M', 'LOT']
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
  <div>
    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="客户样品ID">
          <el-input v-model="model.customerSampleId" placeholder="客户侧样品编号" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="Champ ID">
          <el-input v-model="model.champId" placeholder="Sales Quality 告知客户" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="样品数量">
          <el-input-number v-model="model.sampleQuantity" :min="0" :controls="false" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="单位">
          <el-select v-model="model.uom" clearable>
            <el-option v-for="u in UOMS" :key="u" :label="u" :value="u" />
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="产品标识">
          <el-input v-model="model.productMarking" placeholder="Product Marking" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="应用领域">
          <el-input v-model="model.applicationArea" placeholder="Application Area" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="拒收确认">
          <el-radio-group v-model="model.rejectConfirmed">
            <el-radio-button :value="true">是</el-radio-button>
            <el-radio-button :value="false">否</el-radio-button>
          </el-radio-group>
        </el-form-item>
      </el-col>
      <el-col :span="6" />
    </el-row>

    <!-- The two free-text fields, equal in width and height. -->
    <el-row :gutter="16">
      <el-col :span="12">
        <el-form-item label="描述">
          <el-input
            v-model="model.description"
            type="textarea"
            :rows="3"
            resize="none"
            placeholder="样品描述"
          />
        </el-form-item>
      </el-col>
      <el-col :span="12">
        <el-form-item label="结论">
          <el-input
            v-model="model.conclusion"
            type="textarea"
            :rows="3"
            resize="none"
            placeholder="样品级结论"
          />
        </el-form-item>
      </el-col>
    </el-row>

    <el-divider content-position="left">
      <span class="fs-12 t-4">失效类型（三级级联，逐级收窄）</span>
    </el-divider>

    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="一级">
          <el-select v-model="model.failureTypeL1Code" placeholder="请选择" clearable @change="onLevel1Change">
            <el-option v-for="t in level1Options" :key="t.code" :label="t.name" :value="t.code" />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="二级">
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
        <el-form-item label="三级">
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
  </div>
</template>

<style scoped>
/* Element's number control defaults to a fixed width, which would leave it
   narrower than the inputs beside it. Every short field in this block is the
   same size, and that is what makes the rows read as aligned. */
:deep(.el-input-number) {
  width: 100%;
}
</style>
