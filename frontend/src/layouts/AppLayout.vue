<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { ElMessageBox } from 'element-plus'
import { useUiStore } from '@/stores/ui'
import { useAuthStore } from '@/stores/auth'
import { setLocale } from '@/i18n'
import QmsIcon from '@/components/QmsIcon.vue'

const router = useRouter()
const route = useRoute()
const ui = useUiStore()
const auth = useAuthStore()
const { t } = useI18n()

interface NavItem {
  key: string
  icon: string
  to: string
  permission?: string
}

// Mirrors the prototype's NAV array + NAV_BY_PERSONA gating.
const NAV: NavItem[] = [
  { key: 'home', icon: 'home', to: '/' },
  { key: 'ledger', icon: 'list', to: '/complaints' },
  { key: 'new', icon: 'plus', to: '/complaints/new', permission: 'complaint:create' },
  { key: 'reports', icon: 'chart', to: '/reports' },
  { key: 'kb', icon: 'book', to: '/kb' },
  { key: 'announcement', icon: 'bell', to: '/announcements/manage', permission: 'announcement:manage' },
  { key: 'admin', icon: 'settings', to: '/admin', permission: 'admin.all' }
]

const navItems = computed(() => NAV.filter((n) => !n.permission || auth.can(n.permission)))

const activeKey = computed(() => {
  const metaNav = route.meta.nav as string | undefined
  if (metaNav) return metaNav
  const name = route.name as string
  if (name === 'complaintNew') return 'new'
  if (name === 'home') return 'home'
  if (name === 'ledger' || name === 'complaintDetail') return 'ledger'
  if (name === 'reports') return 'reports'
  if (name === 'kb') return 'kb'
  if (name === 'admin') return 'admin'
  return 'home'
})

const searchText = ref('')
function submitSearch() {
  const q = searchText.value.trim()
  router.push({ path: '/complaints', query: q ? { q } : {} })
}

function onToggleLang() {
  const next = ui.lang === 'zh-CN' ? 'en-US' : 'zh-CN'
  setLocale(next)
  ui.lang = next
}

async function onLogout() {
  try {
    await ElMessageBox.confirm(t('common.logout') + '?', '', { type: 'warning' })
  } catch {
    return
  }
  auth.logout()
  router.push({ name: 'login' })
}
</script>

<template>
  <div class="app" :class="{ 'is-nav-collapsed': ui.navCollapsed }">
    <aside class="app-sidebar">
      <div class="nav-brand">
        <div class="nav-brand-mark">Q</div>
        <div class="nav-brand-text">
          <span class="nav-brand-title">QMS</span>
          <span class="nav-brand-sub">{{ t('brand.sub') }}</span>
        </div>
      </div>

      <nav class="nav-scroll">
        <router-link
          v-for="item in navItems"
          :key="item.key"
          class="nav-item"
          :class="{ 'is-active': activeKey === item.key }"
          :to="item.to"
          :title="t('nav.' + item.key)"
        >
          <span class="nav-item-icon"><QmsIcon :name="item.icon" /></span>
          <span class="nav-item-text">{{ t('nav.' + item.key) }}</span>
        </router-link>
      </nav>

      <div class="nav-foot">
        <button class="nav-collapse-btn" type="button" @click="ui.toggleNav()">
          <QmsIcon name="chevronLeft" :size="15" />
          <span v-if="!ui.navCollapsed">{{ t('nav.collapse') }}</span>
        </button>
      </div>
    </aside>

    <header class="app-topbar">
      <button class="topbar-toggle" type="button" :title="t('nav.home')" @click="ui.toggleNav()">
        <QmsIcon name="menu" />
      </button>

      <div class="topbar-search">
        <QmsIcon name="search" :size="15" />
        <input v-model="searchText" type="search" :placeholder="t('top.searchPlaceholder')" @keyup.enter="submitSearch" />
      </div>

      <div class="topbar-right">
        <button class="icon-btn" type="button" :title="t('top.comfortable') + ' / ' + t('top.compact')" @click="ui.toggleDensity()">
          <QmsIcon name="rows" />
        </button>

        <button class="icon-btn" type="button" :title="t('top.language')" @click="onToggleLang">
          <QmsIcon name="globe" />
        </button>

        <button class="icon-btn" type="button" :title="t('top.todo')">
          <QmsIcon name="bell" />
        </button>

        <div class="row gap-2">
          <span class="fs-12 t-3">{{ auth.user?.name || '' }}</span>
          <button class="icon-btn" type="button" :title="t('common.logout')" @click="onLogout">
            <QmsIcon name="logout" />
          </button>
        </div>
      </div>
    </header>

    <main class="app-main">
      <div class="app-content">
        <router-view />
      </div>
    </main>
  </div>
</template>
