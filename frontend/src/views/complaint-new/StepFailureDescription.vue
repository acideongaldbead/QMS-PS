<script setup lang="ts">
import { useMetaStore } from '@/stores/meta'
import type { CreateComplaintRequest } from '@/api/complaints'
import { UOM_OPTIONS } from './types'

// The wizard owns the model; this step only binds to it.
defineProps<{ form: CreateComplaintRequest }>()
const meta = useMetaStore()
</script>

<template>
  <div>
    <el-row :gutter="16">
      <el-col :span="12">
        <el-form-item label="客户失效模式" required>
          <el-select v-model="form.failureDescription.customerFailureModeCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.failureModes"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="12">
        <el-form-item label="是否直发">
          <el-radio-group v-model="form.failureDescription.shippedDirectly">
            <el-radio-button :value="true">是</el-radio-button>
            <el-radio-button :value="false">否</el-radio-button>
          </el-radio-group>
        </el-form-item>
      </el-col>
    </el-row>

    <el-form-item label="客户失效描述">
      <el-input
        v-model="form.failureDescription.customerFailureDescription"
        type="textarea"
        :rows="3"
        placeholder="客户反馈的失效现象原文"
      />
    </el-form-item>

    <el-form-item label="D0 症状描述">
      <el-input
        v-model="form.failureDescription.d0SymptomsDescription"
        type="textarea"
        :rows="3"
        placeholder="症状描述，可对应上传的 G8D Report"
      />
    </el-form-item>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="失效数量">
          <el-input-number v-model="form.failureDescription.quantityFailing" :min="0" :controls="false" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="失效数量单位">
          <el-select v-model="form.failureDescription.quantityFailingUom" clearable>
            <el-option v-for="u in UOM_OPTIONS" :key="u" :label="u" :value="u" />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="退回数量">
          <el-input-number v-model="form.failureDescription.qualityReturned" :min="0" :controls="false" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="退回数量单位">
          <el-select v-model="form.failureDescription.qualityReturnedUom" clearable>
            <el-option v-for="u in UOM_OPTIONS" :key="u" :label="u" :value="u" />
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="客户采购订单">
          <el-input v-model="form.failureDescription.customerPo" placeholder="Customer PO" />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="销售订单">
          <el-input v-model="form.failureDescription.salesOrder" placeholder="Sales Order" />
        </el-form-item>
      </el-col>
      <el-col :span="8">
        <el-form-item label="供应商发票号">
          <el-input v-model="form.failureDescription.supplierInvoiceNumber" placeholder="Supplier Invoice Number" />
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="8">
        <el-form-item label="收到认可包装">
          <el-input v-model="form.failureDescription.receivedApprPack" placeholder="Received Appr Pack" />
        </el-form-item>
      </el-col>
      <el-col :span="16">
        <el-form-item label="直接沟通记录">
          <el-input v-model="form.failureDescription.directCommunication" placeholder="Direct Communication" />
        </el-form-item>
      </el-col>
    </el-row>

    <el-form-item label="备注">
      <el-input v-model="form.failureDescription.comment" type="textarea" :rows="2" />
    </el-form-item>

    <el-form-item label="投诉/分析结论">
      <el-input
        v-model="form.failureDescription.analysisConclusion"
        type="textarea"
        :rows="2"
        placeholder="可在 D2 验证后回填"
      />
    </el-form-item>
  </div>
</template>
