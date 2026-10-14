<script setup lang="ts">
import { onMounted } from 'vue'
import { useUiStore } from '@/stores/ui'
import { useAuthStore } from '@/stores/auth'

const ui = useUiStore()
const auth = useAuthStore()

onMounted(async () => {
  ui.applyDensity()
  await auth.restore()
})
</script>

<template>
  <router-view />
</template>
