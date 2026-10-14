<script setup lang="ts">
import { watch } from 'vue'
import { useMetaStore } from '@/stores/meta'
import type { CreateComplaintRequest } from '@/api/complaints'

const props = defineProps<{ form: CreateComplaintRequest }>()
const meta = useMetaStore()

/**
 * Picking a product from master data pre-fills everything it can. The user may
 * still override any of it, because the complaint records what was actually
 * shipped rather than what the master data currently says.
 */
function applyProduct(materialCode: string | null) {
  const product = meta.products.find((p) => p.code === materialCode)
  if (!product) return
  props.form.product.productTypeCode = product.productTypeCode ?? props.form.product.productTypeCode
  props.form.product.packingTypeCode = product.packingTypeCode ?? props.form.product.packingTypeCode
  props.form.product.businessGroup = product.businessGroup ?? null
  props.form.product.businessUnit = product.businessUnit ?? null
}

watch(
  () => props.form.product.materialCode,
  (code) => applyProduct(code ?? null)
)
</script>

<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="物料编码（12NC / 9NC）">
          <el-select
            v-model="form.product.materialCode"
            placeholder="从产品主数据选择，可留空"
            filterable
            clearable
          >
            <el-option
              v-for="p in meta.products"
              :key="p.code"
              :label="`${p.code}　${p.description || ''}`"
              :value="p.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="产品类型" required>
          <el-select v-model="form.product.productTypeCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.productTypes"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="包装类型" required>
          <el-select v-model="form.product.packingTypeCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.packingTypes"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="事业部">
          <el-input v-model="form.product.businessGroup" placeholder="Business Group" />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="业务单元">
          <el-input v-model="form.product.businessUnit" placeholder="Business Unit" />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="9NC">
          <el-input v-model="form.product.nc9" placeholder="9 位物料编码" />
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="客户料号">
          <el-input v-model="form.product.customerPartNo" placeholder="Customer Part No." />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="产品状态">
          <el-input v-model="form.product.productStatus" placeholder="产品生命周期状态" />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="受保护">
          <el-radio-group v-model="form.product.isProtected">
            <el-radio-button :value="true">是</el-radio-button>
            <el-radio-button :value="false">否</el-radio-button>
          </el-radio-group>
        </el-form-item>
      </el-col>
    </el-row>

    <el-divider content-position="left">
      <span class="fs-12 t-3">以下四个字段含义待业务方确认（需求文档原文 MAG / 4TG / 5GT / 6GT）</span>
    </el-divider>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="MAG">
          <el-input v-model="form.product.mag" placeholder="待确认" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="4TG">
          <el-input v-model="form.product.tg4" placeholder="待确认" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="5GT">
          <el-input v-model="form.product.tg5" placeholder="待确认" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="6GT">
          <el-input v-model="form.product.tg6" placeholder="待确认" />
        </el-form-item>
      </el-col>
    </el-row>
  </div>
</template>
