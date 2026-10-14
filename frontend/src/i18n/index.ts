import { createI18n } from 'vue-i18n'
import http from '@/api/http'
import zhCN from './locales/zh-CN'
import enUS from './locales/en-US'

const K_LANG = 'qms.lang'

function initialLocale(): 'zh-CN' | 'en-US' {
  try {
    const saved = localStorage.getItem(K_LANG)
    if (saved === 'en-US' || saved === 'zh-CN') return saved
  } catch {
    /* private mode */
  }
  return 'zh-CN'
}

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: initialLocale(),
  fallbackLocale: 'zh-CN',
  messages: { 'zh-CN': zhCN, 'en-US': enUS }
})

export function setLocale(locale: 'zh-CN' | 'en-US'): void {
  i18n.global.locale.value = locale
  try {
    localStorage.setItem(K_LANG, locale)
  } catch {
    /* private mode */
  }
  document.documentElement.lang = locale
}

/**
 * Overlay the admin-maintained 翻译配置 (translation table) on top of the static
 * bundles. Called once after login; failures are non-fatal.
 */
export async function loadDbTranslations(): Promise<void> {
  try {
    const { data } = await http.get<Record<string, Record<string, string>>>('/i18n/messages')
    const known = i18n.global.availableLocales as readonly string[]
    for (const [locale, entries] of Object.entries(data || {})) {
      if (!known.includes(locale)) continue
      i18n.global.mergeLocaleMessage(locale as 'zh-CN' | 'en-US', entries)
    }
  } catch {
    /* keep the bundled messages */
  }
}

export default i18n
