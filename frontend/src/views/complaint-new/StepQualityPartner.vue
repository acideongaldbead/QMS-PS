<script setup lang="ts">
import { ref, watch } from 'vue'
import { masterDataApi, type Contact, type Option } from '@/api/masterData'
import { useMetaStore } from '@/stores/meta'
import type { CreateComplaintRequest } from '@/api/complaints'

const props = defineProps<{ form: CreateComplaintRequest }>()
const meta = useMetaStore()

const contacts = ref<Contact[]>([])
const shipToPlants = ref<Option[]>([])
const loadingContacts = ref(false)

/**
 * Contacts and ship-to plants belong to one customer, so they are fetched per
 * selection rather than cached globally. Changing the customer invalidates both,
 * and clearing them avoids submitting a contact from the previous company.
 */
async function loadCustomerDetails(customerCode: string | null) {
  contacts.value = []
  shipToPlants.value = []
  props.form.qualityPartner.contactPersonId = ''
  props.form.qualityPartner.shipToSoldToCode = null
  if (!customerCode) return

  loadingContacts.value = true
  try {
    const [c, s] = await Promise.all([
      masterDataApi.contactsOf(customerCode),
      masterDataApi.shipToOf(customerCode)
    ])
    contacts.value = c
    shipToPlants.value = s
  } finally {
    loadingContacts.value = false
  }
}

watch(
  () => props.form.qualityPartner.qualityPartnerCode,
  (code) => {
    void loadCustomerDetails(code)
  },
  { immediate: true }
)

function selectedContactEmail(): string {
  const id = props.form.qualityPartner.contactPersonId
  return contacts.value.find((c) => c.id === id)?.email ?? ''
}
</script>

<template>
  <div>
    <p class="form-hint">质量合作伙伴来自客户主数据，不可在此新建；选定后联系人与收货方选项随之收窄。</p>

    <!-- One uniform 4-column grid: every field is span 6, so columns line up
         vertically across rows rather than stepping in and out. -->
    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="质量合作伙伴" required>
          <el-select
            v-model="form.qualityPartner.qualityPartnerCode"
            placeholder="请选择客户"
            filterable
            clearable
          >
            <el-option v-for="c in meta.customers" :key="c.code" :label="c.name" :value="c.code">
              <span>{{ c.name }}</span>
              <span class="option-sub">{{ c.code }}</span>
            </el-option>
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="应用" required>
          <el-radio-group v-model="form.qualityPartner.application">
            <el-radio-button value="Yes">是</el-radio-button>
            <el-radio-button value="No">否</el-radio-button>
          </el-radio-group>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="联系人" required>
          <el-select
            v-model="form.qualityPartner.contactPersonId"
            placeholder="请先选择客户"
            :loading="loadingContacts"
            :disabled="!form.qualityPartner.qualityPartnerCode"
            clearable
          >
            <el-option v-for="c in contacts" :key="c.id" :label="c.name" :value="c.id" />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="收货/售达方">
          <el-select
            v-model="form.qualityPartner.shipToSoldToCode"
            placeholder="请先选择客户"
            :disabled="!form.qualityPartner.qualityPartnerCode"
            clearable
          >
            <el-option v-for="s in shipToPlants" :key="s.code" :label="s.name" :value="s.code" />
          </el-select>
        </el-form-item>
      </el-col>
    </el-row>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="子分部" required>
          <el-select v-model="form.qualityPartner.subSegmentCode" placeholder="请选择" clearable>
            <el-option
              v-for="item in meta.subSegments"
              :key="item.code"
              :label="item.nameCn"
              :value="item.code"
            />
          </el-select>
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="HS 编码">
          <el-input v-model="form.qualityPartner.hsCode" placeholder="海关商品编码" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="ECCN">
          <el-input v-model="form.qualityPartner.eccn" placeholder="出口管制分类编码" />
        </el-form-item>
      </el-col>
      <el-col :span="6" />
    </el-row>

    <el-row :gutter="16">
      <el-col :span="6">
        <el-form-item label="最终客户">
          <el-input v-model="form.qualityPartner.endCustomer" placeholder="终端客户名称" />
        </el-form-item>
      </el-col>
      <el-col :span="6">
        <el-form-item label="联系人邮箱">
          <el-input :model-value="selectedContactEmail()" disabled placeholder="选择联系人后带出" />
        </el-form-item>
      </el-col>
      <el-col :span="12">
        <p class="form-note">该邮箱在 8D 报告发送时自动填充为收件人。</p>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped>
.form-hint {
  margin: 0 0 var(--sp-4);
  font-size: var(--fs-12);
  color: var(--t-3);
}

/* Sits beside the email field, vertically centred against the input. */
.form-note {
  margin: 0;
  padding-top: 9px;
  font-size: var(--fs-12);
  color: var(--t-4);
}

/* Keeps the collapsed select to the customer name so it never truncates; the
   code stays visible inside the dropdown. */
.option-sub {
  float: right;
  margin-left: 16px;
  color: var(--t-4);
  font-size: var(--fs-12);
}
</style>
