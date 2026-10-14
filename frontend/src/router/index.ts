import { createRouter, createWebHashHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

// Hash history on purpose: the production build is served as a single Spring
// Boot jar, so deep links must not depend on a server-side rewrite rule.
const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/LoginView.vue'),
    meta: { public: true }
  },
  {
    path: '/',
    component: () => import('@/layouts/AppLayout.vue'),
    children: [
      { path: '', name: 'home', component: () => import('@/views/HomeView.vue') },
      { path: 'complaints', name: 'ledger', component: () => import('@/views/LedgerView.vue') },
      {
        path: 'complaints/new',
        name: 'complaintNew',
        component: () => import('@/views/ComplaintCreateView.vue'),
        meta: { permission: 'complaint:create' }
      },
      {
        path: 'complaints/:id',
        name: 'complaintDetail',
        component: () => import('@/views/ComplaintDetailView.vue'),
        props: true,
        meta: { nav: 'ledger' }
      },
      {
        path: 'complaints/:id/report/:reportId',
        name: 'report8d',
        component: () => import('@/views/Report8DView.vue'),
        props: true,
        meta: { nav: 'ledger' }
      },
      {
        path: 'complaints/:id/report/:reportId/send',
        name: 'reportSend',
        component: () => import('@/views/ReportSendView.vue'),
        props: true,
        meta: { nav: 'ledger', permission: 'report:send' }
      },
      { path: 'reports', name: 'reports', component: () => import('@/views/ReportsView.vue') },
      {
        path: 'kb',
        name: 'kb',
        component: () => import('@/views/KnowledgeView.vue'),
        meta: { permission: 'knowledge:view' }
      },
      {
        path: 'admin',
        name: 'admin',
        component: () => import('@/views/AdminView.vue'),
        meta: { permission: 'admin.all' }
      }
    ]
  },
  { path: '/:pathMatch(.*)*', redirect: '/' }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.restore()

  if (to.meta.public) {
    return auth.isAuthenticated ? { name: 'home' } : true
  }

  if (!auth.isAuthenticated) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  const permission = to.meta.permission as string | undefined
  if (permission && !auth.can(permission)) {
    return { name: 'home' }
  }

  return true
})

export default router
