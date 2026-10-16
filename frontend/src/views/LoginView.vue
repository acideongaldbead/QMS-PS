<script setup lang="ts">
import { reactive, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { useAuthStore } from '@/stores/auth'
import { errorMessage } from '@/api/http'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()
const { t } = useI18n()

const form = reactive({ username: '', password: '' })
const loading = ref(false)

async function submit() {
  if (!form.username || !form.password) {
    ElMessage.warning(t('login.subtitle'))
    return
  }
  loading.value = true
  try {
    await auth.login(form.username, form.password)
    // A forced password change wins over wherever they were heading: the server
    // refuses everything else until it is done.
    if (auth.mustChangePwd) {
      router.push({ name: 'changePassword' })
      return
    }
    const redirect = (route.query.redirect as string) || '/'
    router.push(redirect)
  } catch (e) {
    ElMessage.error(errorMessage(e) || t('login.failed'))
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-wrap">
    <form class="login-card" @submit.prevent="submit">
      <h1 class="login-title">{{ t('login.title') }}</h1>
      <p class="t-3 fs-13">{{ t('login.subtitle') }}</p>

      <label class="login-field">
        <span class="fs-12 t-3">{{ t('login.username') }}</span>
        <input v-model="form.username" type="text" autocomplete="username" />
      </label>

      <label class="login-field">
        <span class="fs-12 t-3">{{ t('login.password') }}</span>
        <input v-model="form.password" type="password" autocomplete="current-password" />
      </label>

      <button class="btn btn-primary btn-lg btn-block" type="submit" :disabled="loading">
        {{ loading ? t('common.loading') : t('login.submit') }}
      </button>
    </form>
  </div>
</template>

<style scoped>
.login-wrap {
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: var(--bg-app);
}

.login-card {
  width: 360px;
  padding: var(--sp-8);
  background: var(--bg-surface);
  border: 1px solid var(--bd-1);
  border-radius: var(--r-4);
  box-shadow: var(--sh-3);
  display: flex;
  flex-direction: column;
  gap: var(--sp-3);
}

.login-title {
  font-size: var(--fs-18);
  margin: 0 0 var(--sp-1);
}

.login-field {
  display: flex;
  flex-direction: column;
  gap: var(--sp-1);
}

.login-field input {
  height: var(--d-input-h);
  padding: 0 var(--sp-3);
  border: 1px solid var(--bd-2);
  border-radius: var(--r-2);
  background: var(--bg-surface);
  color: var(--t-1);
}

.login-field input:focus {
  outline: none;
  border-color: var(--bd-focus);
  box-shadow: var(--sh-focus);
}

.btn-block {
  margin-top: var(--sp-2);
}
</style>
