<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import QmsIcon from '@/components/QmsIcon.vue'

defineProps<{ titleKey: string; icon?: string }>()
const { t } = useI18n()
</script>

<template>
  <div>
    <div class="page-head">
      <div>
        <h1>{{ t(titleKey) }}</h1>
      </div>
    </div>

    <div class="card">
      <div class="card-body">
        <div class="row gap-3">
          <QmsIcon :name="icon || 'file'" :size="20" />
          <span class="t-3 fs-13">{{ t('common.notImplemented') }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
