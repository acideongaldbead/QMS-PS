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
        path: 'announcements/manage',
        name: 'announcementManage',
        component: () => import('@/views/AnnouncementManageView.vue'),
        meta: { permission: 'announcement:manage', nav: 'announcement' }
      },
      {
        path: 'admin',
        name: 'admin',
        component: () => import('@/views/AdminView.vue'),
        meta: { permission: 'admin.all' }
      },
      {
        // Not in the sidebar: reachable only when the server says a password
        // change is due, or deliberately by someone changing their own.
        path: 'change-password',
        name: 'changePassword',
        component: () => import('@/views/ChangePasswordView.vue')
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

  // A forced password change confines the session to the change screen: the
  // server answers 403 everywhere else, so sending them anywhere else would only
  // produce failing requests.
  if (auth.mustChangePwd && to.name !== 'changePassword') {
    return { name: 'changePassword' }
  }

  const permission = to.meta.permission as string | undefined
  if (permission && !auth.can(permission)) {
    return { name: 'home' }
  }

  return true
})

export default router
