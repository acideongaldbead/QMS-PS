<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { errorMessage } from '@/api/http'
import { useAuthStore } from '@/stores/auth'

/**
 * Changing your own password (requirement 3.12).
 *
 * Two ways in: an administrator reset the password (or the account still holds the
 * seed password), so the server confines the session here until it is changed; or
 * someone simply wants a new one. The server refuses every other API while the
 * forced-change flag is set, which is why the router sends here and nowhere else.
 */
const router = useRouter()
const auth = useAuthStore()
const { t } = useI18n()

/** Mirrors PasswordPolicy.MIN_LENGTH on the server. */
const MIN_PASSWORD = 8

const forced = computed(() => auth.mustChangePwd)

const form = reactive({ oldPassword: '', newPassword: '', confirmPassword: '' })
const saving = ref(false)

async function submit() {
  if (!form.oldPassword) {
    ElMessage.warning(t('changePwd.oldRequired'))
    return
  }
  if (form.newPassword.length < MIN_PASSWORD) {
    ElMessage.warning(t('changePwd.tooShort'))
    return
  }
  if (form.newPassword !== form.confirmPassword) {
    ElMessage.warning(t('changePwd.mismatch'))
    return
  }
  if (form.newPassword === form.oldPassword) {
    ElMessage.warning(t('changePwd.sameAsOld'))
    return
  }
  saving.value = true
  try {
    await auth.changePassword(form.oldPassword, form.newPassword)
    ElMessage.success(t('changePwd.done'))
    // The forced-change flag is gone; the guard lets every other route through now.
    router.push('/')
  } catch (e) {
    ElMessage.error(errorMessage(e))
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <div class="page-head">
      <div class="page-title-row">
        <div>
          <h1 class="page-title">{{ t('changePwd.title') }}</h1>
          <div class="page-sub">{{ t('changePwd.sub') }}</div>
        </div>
      </div>
    </div>

    <div class="card cp-card">
      <div class="card-body">
        <div v-if="forced" class="cp-notice" data-cp-forced>{{ t('changePwd.forced') }}</div>

        <el-form label-width="110px" label-position="left">
          <el-form-item :label="t('changePwd.old')" required>
            <div class="cp-field" data-cp-old>
              <el-input v-model="form.oldPassword" type="password" show-password maxlength="72" />
            </div>
          </el-form-item>

          <el-form-item :label="t('changePwd.new')" required>
            <div class="cp-field" data-cp-new>
              <el-input v-model="form.newPassword" type="password" show-password maxlength="72" />
            </div>
          </el-form-item>

          <el-form-item :label="t('changePwd.confirm')" required>
            <div class="cp-field" data-cp-confirm>
              <el-input
                v-model="form.confirmPassword"
                type="password"
                show-password
                maxlength="72"
                @keyup.enter="submit"
              />
            </div>
          </el-form-item>
        </el-form>

        <div class="cp-actions">
          <el-button type="primary" :loading="saving" data-cp-save @click="submit">
            {{ t('changePwd.submit') }}
          </el-button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* A single-column form reads better than a full-width card. */
.cp-card {
  max-width: 560px;
}

.cp-field {
  width: 100%;
}

.cp-notice {
  margin-bottom: var(--sp-4);
  padding: var(--sp-3) var(--sp-3);
  border: 1px solid var(--c-warning-border);
  background: var(--c-warning-soft);
  border-radius: var(--r-2);
  color: #B45309;
  font-size: var(--fs-12);
}

.cp-actions {
  display: flex;
  justify-content: flex-end;
}
</style>
