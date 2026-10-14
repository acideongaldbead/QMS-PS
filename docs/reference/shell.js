/* ==========================================================================
   QMS 原型 · 应用外壳
   左侧导航 + 顶栏（全局搜索 / 待办 / 中英切换 / 角色切换 / 用户）
   用法：页面 <body data-nav="home" data-title="首页工作台" data-sub="...">
   外壳自动注入 #qmsSidebar / #qmsTopbar
   ========================================================================== */

window.QMSShell = (function () {
  'use strict';

  /* ---------------- 图标库 ---------------- */

  var ICONS = {
    home:     '<path d="M3 10.6 12 3.5l9 7.1"/><path d="M5.4 9.6V20h13.2V9.6"/><path d="M9.8 20v-5.4h4.4V20"/>',
    complaint:'<path d="M8 3.5h8a1.6 1.6 0 0 1 1.6 1.6v14.8a1.6 1.6 0 0 1-1.6 1.6H8a1.6 1.6 0 0 1-1.6-1.6V5.1A1.6 1.6 0 0 1 8 3.5Z"/><path d="M9.4 3.5v2.2h5.2V3.5"/><path d="M9.4 11.5h5.2M9.4 15.2h3.4"/>',
    ledger:   '<path d="M4.5 4.6h15v14.8h-15z"/><path d="M4.5 9.2h15M9.6 9.2v10.2"/>',
    plus:     '<path d="M12 5.5v13M5.5 12h13"/>',
    chart:    '<path d="M4 20.2h16"/><path d="M7.2 20.2V11M12 20.2V4.8M16.8 20.2v-6.4"/>',
    book:     '<path d="M4.4 4.6h6.2a2.4 2.4 0 0 1 2.4 2.4v12.4a1.8 1.8 0 0 0-1.8-1.8H4.4z"/><path d="M19.6 4.6h-6.2A2.4 2.4 0 0 0 11 7v12.4a1.8 1.8 0 0 1 1.8-1.8h6.8z"/>',
    settings: '<circle cx="12" cy="12" r="3.1"/><path d="M19.4 14.4a1.6 1.6 0 0 0 .32 1.76l.06.06a1.9 1.9 0 1 1-2.7 2.7l-.06-.06a1.6 1.6 0 0 0-1.76-.32 1.6 1.6 0 0 0-1 1.47v.17a1.9 1.9 0 1 1-3.8 0v-.09a1.6 1.6 0 0 0-1.05-1.47 1.6 1.6 0 0 0-1.76.32l-.06.06a1.9 1.9 0 1 1-2.7-2.7l.06-.06a1.6 1.6 0 0 0 .32-1.76 1.6 1.6 0 0 0-1.47-1H3.6a1.9 1.9 0 0 1 0-3.8h.09A1.6 1.6 0 0 0 5.16 9.1a1.6 1.6 0 0 0-.32-1.76l-.06-.06a1.9 1.9 0 1 1 2.7-2.7l.06.06a1.6 1.6 0 0 0 1.76.32H9.4a1.6 1.6 0 0 0 1-1.47V3.3a1.9 1.9 0 1 1 3.8 0v.09a1.6 1.6 0 0 0 1 1.47 1.6 1.6 0 0 0 1.76-.32l.06-.06a1.9 1.9 0 1 1 2.7 2.7l-.06.06a1.6 1.6 0 0 0-.32 1.76v.08a1.6 1.6 0 0 0 1.47 1h.17a1.9 1.9 0 1 1 0 3.8h-.09a1.6 1.6 0 0 0-1.47 1Z"/>',
    search:   '<circle cx="11" cy="11" r="6.4"/><path d="m19.6 19.6-4.2-4.2"/>',
    bell:     '<path d="M18 8.6a6 6 0 1 0-12 0c0 6-2.4 7.8-2.4 7.8h16.8S18 14.6 18 8.6"/><path d="M13.7 20.2a2 2 0 0 1-3.4 0"/>',
    globe:    '<circle cx="12" cy="12" r="8.6"/><path d="M3.4 12h17.2"/><path d="M12 3.4a15 15 0 0 1 0 17.2 15 15 0 0 1 0-17.2"/>',
    menu:     '<path d="M4 6.5h16M4 12h16M4 17.5h16"/>',
    chev:     '<path d="m6 9 6 6 6-6"/>',
    user:     '<circle cx="12" cy="8" r="3.6"/><path d="M4.8 20.4a7.2 7.2 0 0 1 14.4 0"/>',
    logout:   '<path d="M9.5 20.5H6a1.8 1.8 0 0 1-1.8-1.8V5.3A1.8 1.8 0 0 1 6 3.5h3.5"/><path d="M15.5 16.2 20 12l-4.5-4.2"/><path d="M20 12H9.8"/>',
    help:     '<circle cx="12" cy="12" r="8.6"/><path d="M9.8 9.6a2.3 2.3 0 1 1 3.1 2.2c-.7.3-1 .9-1 1.6v.4"/><path d="M12 17.1h.01"/>',
    bolt:     '<path d="M13.2 3.2 5.4 13.4h5.2l-1 7.4 8-10.2h-5.3z"/>',
    density:  '<path d="M4 6.5h16"/><path d="M4 10.5h16"/><path d="M4 15h16"/><path d="M4 19h16"/>',
    collapse: '<path d="m6 15 6-6 6 6"/>',
    chevLeft: '<path d="m14 6.5-5.5 5.5 5.5 5.5"/>'
  };

  function svg(name, cls) {
    var p = ICONS[name] || '';
    return '<svg class="' + (cls || '') + '" viewBox="0 0 24 24" aria-hidden="true">' + p + '</svg>';
  }

  /* ---------------- 导航结构 ---------------- */

  var NAV = [
    { key: 'home',    cn: '首页工作台',   en: 'Home',             icon: 'home',   href: 'index.html' },
    { key: 'ledger',  cn: '问题解决汇总', en: 'Complaint Ledger', icon: 'ledger', href: 'complaints.html' },
    { key: 'new',     cn: '登记投诉',     en: 'New Complaint',    icon: 'plus',   href: 'complaint-new.html' },
    { key: 'reports', cn: '报表',         en: 'Reports',          icon: 'chart',  href: 'reports.html' },
    { key: 'kb',      cn: '知识中心',     en: 'Knowledge Center', icon: 'book',   href: 'kb.html' },
    { key: 'admin',   cn: '系统管理',     en: 'System Admin',     icon: 'settings', href: 'admin.html' }
  ];

  /* 各角色可见的导航（原型演示权限差异） */
  var NAV_BY_PERSONA = {
    sales:  ['home', 'ledger', 'new', 'reports', 'kb'],
    qe:     ['home', 'ledger', 'new', 'reports', 'kb'],
    fa:     ['home', 'ledger', 'new', 'reports', 'kb'],
    owner:  ['home', 'ledger', 'new', 'reports', 'kb'],
    appr:   ['home', 'ledger', 'new', 'reports', 'kb'],
    mgr:    ['home', 'ledger', 'new', 'reports', 'kb'],
    admin:  ['home', 'ledger', 'new', 'reports', 'kb', 'admin']
  };

  /* 角色可用动作（页面级按钮门控） */
  var PERMS = {
    sales:  ['complaint.view', 'complaint.create', 'complaint.edit', 'report.send', 'report.edit', 'sample.edit'],
    qe:     ['complaint.view', 'complaint.create', 'complaint.edit', 'sample.edit', 'verify.edit', 'action.edit'],
    fa:     ['complaint.view', 'verify.edit'],
    owner:  ['complaint.view', 'complaint.edit', 'action.edit', 'report.edit'],
    appr:   ['complaint.view', 'report.approve'],
    mgr:    ['complaint.view', 'report.view'],
    admin:  ['complaint.view', 'admin.all']
  };

  var LS_KEY = 'qms.persona';
  var LS_LANG = 'qms.lang';
  var LS_DENSITY = 'qms.density';
  var LS_NAV = 'qms.navCollapsed';

  /* file:// 下部分浏览器会禁用 localStorage，降级为内存存储，避免整页脚本中断 */
  var LS = (function () {
    var mem = {};
    return {
      get: function (k) { try { return window.localStorage.getItem(k); } catch (e) { return mem[k] || null; } },
      set: function (k, v) { try { window.localStorage.setItem(k, v); } catch (e) { mem[k] = v; } }
    };
  })();

  var current = LS.get(LS_KEY) || 'qe';
  var lang = LS.get(LS_LANG) || 'cn';

  /* 信息密度：comfortable（默认，13.5px 表格字号）/ compact（一屏看更多行） */
  var density = LS.get(LS_DENSITY) === 'compact' ? 'compact' : 'comfortable';

  function persona() {
    return QMS.personas.filter(function (p) { return p.key === current; })[0] || QMS.personas[0];
  }
  function can(action) {
    return (PERMS[current] || []).indexOf(action) >= 0;
  }

  /* ---------------- 中英文案（界面级） ---------------- */

  var I18N = {
    cn: {
      'nav.home': '首页工作台', 'nav.ledger': '问题解决汇总', 'nav.new': '登记投诉',
      'nav.reports': '报表', 'nav.kb': '知识中心', 'nav.admin': '系统管理',
      'search.placeholder': '搜索投诉 ID / 客户 / 产品…',
      'top.todos': '待办', 'top.help': '帮助', 'top.profile': '个人设置', 'top.logout': '退出登录',
      'lang.label': '中文', 'role.label': '当前角色',
      'common.view': '查看', 'common.edit': '编辑', 'common.delete': '删除', 'common.save': '保存',
      'common.cancel': '取消', 'common.confirm': '确定', 'common.submit': '提交', 'common.reset': '重置',
      'common.search': '查询', 'common.export': '导出', 'common.add': '新增', 'common.more': '更多',
      'common.back': '返回', 'common.close': '关闭', 'common.all': '全部', 'common.optional': '选填',
      'page.home': '首页工作台', 'page.ledger': '问题解决汇总', 'page.new': '登记投诉',
      'page.detail': '投诉详情', 'page.why': '3x5 Why 与鱼骨图在线编辑',
      'page.report': '8D 报告', 'page.send': '发送 8D 报告给客户',
      'page.reports': '报表', 'page.kb': '知识中心', 'page.admin': '系统管理',
      'stage.D0': '问题登记', 'stage.D1': '成立团队', 'stage.D2': '验证与问题定义',
      'stage.D3': '遏制措施', 'stage.D4': '根因分析', 'stage.D5': '纠正措施',
      'stage.D6': '措施实施与验证', 'stage.D7': '预防再发生', 'stage.D8': '报告与结案'
    },
    en: {
      'nav.home': 'Home', 'nav.ledger': 'Complaint Ledger', 'nav.new': 'New Complaint',
      'nav.reports': 'Reports', 'nav.kb': 'Knowledge Center', 'nav.admin': 'System Admin',
      'search.placeholder': 'Search complaint ID / customer / product…',
      'top.todos': 'To-do', 'top.help': 'Help', 'top.profile': 'Profile', 'top.logout': 'Sign out',
      'lang.label': 'EN', 'role.label': 'Role',
      'common.view': 'View', 'common.edit': 'Edit', 'common.delete': 'Delete', 'common.save': 'Save',
      'common.cancel': 'Cancel', 'common.confirm': 'OK', 'common.submit': 'Submit', 'common.reset': 'Reset',
      'common.search': 'Search', 'common.export': 'Export', 'common.add': 'Add', 'common.more': 'More',
      'common.back': 'Back', 'common.close': 'Close', 'common.all': 'All', 'common.optional': 'Optional',
      'page.home': 'Home', 'page.ledger': 'Complaint Ledger', 'page.new': 'New Complaint',
      'page.detail': 'Complaint Detail', 'page.why': '3x5 Why & Fishbone Editor',
      'page.report': '8D Report', 'page.send': 'Send 8D Report to Customer',
      'page.reports': 'Reports', 'page.kb': 'Knowledge Center', 'page.admin': 'System Admin',
      'stage.D0': 'Registration', 'stage.D1': 'Team', 'stage.D2': 'Verification',
      'stage.D3': 'Containment', 'stage.D4': 'Root Cause', 'stage.D5': 'Corrective Actions',
      'stage.D6': 'Implementation', 'stage.D7': 'Prevent Recurrence', 'stage.D8': 'Report & Closure'
    }
  };

  function t(key, fallback) {
    var d = I18N[lang] || I18N.cn;
    return d[key] || fallback || key;
  }

  /* ---------------- 渲染：侧边栏 ---------------- */

  function renderSidebar() {
    var host = document.getElementById('qmsSidebar');
    if (!host) { return; }

    var activeKey = document.body.dataset.nav || '';
    var visible = NAV_BY_PERSONA[current] || [];
    var todoCount = QMS.todos.filter(function (x) { return x.persona.indexOf(current) >= 0; }).length;

    var html = ''
      + '<div class="nav-brand">'
      +   '<div class="nav-brand-mark">QS</div>'
      +   '<div class="nav-brand-text">'
      +     '<span class="nav-brand-title">QMS 问题解决</span>'
      +     '<span class="nav-brand-sub">Problem Solving System</span>'
      +   '</div>'
      + '</div>'
      + '<nav class="nav-scroll">';

    visible.forEach(function (key) {
      var item = NAV.filter(function (n) { return n.key === key; })[0];
      if (!item) { return; }
      var isOn = (activeKey === item.key);
      html += navLink(item.href, isOn, item.icon, t('nav.' + item.key, item.cn),
                      (item.key === 'home' && todoCount) ? todoCount : null);
    });

    html += '</nav>'
      + '<button class="nav-collapse-btn" id="navCollapseBtn" title="收起 / 展开导航">'
      +   svg('chevLeft', '') + '<span>收起导航</span>'
      + '</button>'
      + '<div class="nav-foot">Demo Prototype · v0.1</div>';

    host.innerHTML = html;
  }

  function navLink(href, isOn, icon, label, badge) {
    var cls = 'nav-item' + (isOn ? ' is-active' : '');
    var attrs = href ? ' href="' + href + '"' : ' href="#" data-missing="1"';
    var b = badge ? '<span class="nav-item-count">' + badge + '</span>' : '';
    return '<a class="' + cls + '"' + attrs + ' title="' + label + '">'
         + svg(icon, 'nav-item-icon')
         + '<span class="nav-item-text">' + label + '</span>' + b + '</a>';
  }

  /* ---------------- 渲染：顶栏 ---------------- */

  function renderTopbar() {
    var host = document.getElementById('qmsTopbar');
    if (!host) { return; }

    var p = persona();
    var u = QMS.user(p.user);
    var todoCount = QMS.todos.filter(function (x) { return x.persona.indexOf(current) >= 0; }).length;

    host.innerHTML = ''
      + '<button class="topbar-toggle" id="navToggle" title="收起 / 展开导航">' + svg('menu', '') + '</button>'

      + '<div class="topbar-search">' + svg('search', '')
      +   '<input type="search" placeholder="' + t('search.placeholder') + '" id="globalSearch">'
      + '</div>'

      + '<div class="topbar-right">'

      // 待办
      +   '<button class="icon-btn" id="todoBtn" title="' + t('top.todos') + '">' + svg('bell', '')
      +     (todoCount ? '<span class="dot">' + todoCount + '</span>' : '') + '</button>'

      // 角色切换
      +   '<div class="role-switch" style="position:relative">'
      +     '<button class="switch-btn" id="roleBtn" title="切换演示角色（原型专用）">'
      +       '<span class="role-dot"></span>'
      +       '<span class="role-label">' + p.name + '</span>'
      +       svg('chev', 'caret')
      +     '</button>'
      +     '<div class="menu" id="roleMenu" style="right:0;top:40px;min-width:260px">'
      +       '<div class="menu-head">切换演示角色 · ' + u.name + '</div>'
      +       QMS.personas.map(function (x) {
                var on = x.key === current;
                return '<button class="menu-item' + (on ? ' is-on' : '') + '" data-persona="' + x.key + '">'
                     + '<span class="grow" style="text-align:left">' + x.name
                     + '<span class="fs-11 t-3" style="display:block">' + x.hint + '</span></span>'
                     + (on ? '<svg class="check-mark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" style="width:14px;height:14px"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>' : '')
                     + '</button>';
              }).join('')
      +     '</div>'
      +   '</div>'

      // 信息密度切换
      +   '<button class="switch-btn" id="densityBtn" title="切换信息密度：舒适（默认，字号更大更好读）/ 紧凑（一屏看更多行）">'
      +     svg('density', '')
      +     '<span>' + (density === 'compact' ? '紧凑' : '舒适') + '</span></button>'

      // 语言切换
      +   '<button class="switch-btn" id="langBtn" title="一键中英文切换">' + svg('globe', '')
      +     '<span>' + (lang === 'cn' ? '中文' : 'EN') + '</span></button>'

      // 用户
      +   '<div class="role-switch" style="position:relative">'
      +     '<button class="user-chip" id="userBtn">'
      +       '<span class="avatar">' + u.name.slice(0, 1) + '</span>'
      +       '<span class="fs-13">' + u.name + '</span>'
      +       svg('chev', 'caret')
      +     '</button>'
      +     '<div class="menu" id="userMenu" style="right:0;top:42px">'
      +       '<div class="menu-head">' + u.name + ' · ' + u.title + '</div>'
      +       '<button class="menu-item">' + svg('user', '') + t('top.profile') + '</button>'
      +       '<button class="menu-item">' + svg('help', '') + t('top.help') + '</button>'
      +       '<div class="menu-sep"></div>'
      +       '<button class="menu-item is-danger">' + svg('logout', '') + t('top.logout') + '</button>'
      +     '</div>'
      +   '</div>'

      + '</div>';
  }

  /* ---------------- 渲染：页面标题区 ---------------- */

  function renderPageHead() {
    var host = document.getElementById('qmsPageHead');
    if (!host) { return; }
    // 页头由各页自行填充（含操作按钮），外壳只补面包屑
    var bc = host.dataset.breadcrumb;
    if (!bc) { return; }
    var parts = bc.split('|');
    var crumbs = parts.map(function (s, i) {
      var last = i === parts.length - 1;
      return last
        ? '<span class="cur">' + s + '</span>'
        : '<a href="#">' + s + '</a><span class="sep">/</span>';
    }).join('');
    host.insertAdjacentHTML('afterbegin', '<div class="breadcrumb">' + crumbs + '</div>');
  }

  /* ---------------- 事件绑定 ---------------- */

  function bind() {
    var navToggle = document.getElementById('navToggle');
    if (navToggle) { navToggle.addEventListener('click', toggleNav); }
    var navCollapseBtn = document.getElementById('navCollapseBtn');
    if (navCollapseBtn) { navCollapseBtn.addEventListener('click', toggleNav); }

    // 角色菜单
    wireMenu('roleBtn', 'roleMenu');
    wireMenu('userBtn', 'userMenu');

    // 角色切换
    var roleMenu = document.getElementById('roleMenu');
    if (roleMenu) {
      roleMenu.addEventListener('click', function (e) {
        var btn = e.target.closest('[data-persona]');
        if (!btn) { return; }
        LS.set(LS_KEY, btn.dataset.persona);
        location.reload();
      });
    }

    // 信息密度切换（纯 CSS，无需重载）
    var densityBtn = document.getElementById('densityBtn');
    if (densityBtn) {
      densityBtn.addEventListener('click', function () {
        density = density === 'compact' ? 'comfortable' : 'compact';
        LS.set(LS_DENSITY, density);
        applyDensity();
        if (window.QMSUI) {
          QMSUI.toast('info', density === 'compact' ? '已切换为紧凑密度' : '已切换为舒适密度',
            density === 'compact'
              ? '表格字号 12.5px、行距收紧，一屏可看更多行。'
              : '表格字号 13.5px、行距放宽，适合长时间查看。');
        }
      });
    }

    // 语言切换
    var langBtn = document.getElementById('langBtn');
    if (langBtn) {
      langBtn.addEventListener('click', function () {
        LS.set(LS_LANG, lang === 'cn' ? 'en' : 'cn');
        location.reload();
      });
    }

    // 未实现页面
    document.addEventListener('click', function (e) {
      var a = e.target.closest('a[data-missing]');
      if (a) {
        e.preventDefault();
        QMSUI.toast('info', '该模块暂未开放', a.textContent.trim() + ' 暂未开放。');
      }
    });

    // 待办铃铛
    var todoBtn = document.getElementById('todoBtn');
    if (todoBtn) {
      todoBtn.addEventListener('click', function () { location.href = 'index.html#todos'; });
    }

    // 全局搜索
    var gs = document.getElementById('globalSearch');
    if (gs) {
      gs.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && gs.value.trim()) {
          location.href = 'complaints.html?q=' + encodeURIComponent(gs.value.trim());
        }
      });
    }
  }

  function toggleNav() {
    var app = document.querySelector('.app');
    if (!app) { return; }
    var collapsed = !app.classList.contains('is-nav-collapsed');
    app.classList.toggle('is-nav-collapsed', collapsed);
    LS.set(LS_NAV, collapsed ? '1' : '0');
  }

  function wireMenu(btnId, menuId) {
    var btn = document.getElementById(btnId), menu = document.getElementById(menuId);
    if (!btn || !menu) { return; }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      var wasOpen = menu.classList.contains('is-open');
      document.querySelectorAll('.menu.is-open').forEach(function (m) { m.classList.remove('is-open'); });
      if (!wasOpen) { menu.classList.add('is-open'); }
    });
    document.addEventListener('click', function () { menu.classList.remove('is-open'); });
    menu.addEventListener('click', function (e) { e.stopPropagation(); });
  }

  /* ---------------- 国际化应用 ---------------- */

  function applyI18n() {
    if (lang === 'cn') { return; }
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var v = I18N.en[el.dataset.i18n];
      if (v) { el.textContent = v; }
    });
  }

  /* ---------------- 初始化 ---------------- */

  function applyDensity() {
    document.documentElement.dataset.density = density;
  }

  /* 折叠态由 localStorage 记住，跨页面跳转不回弹 */
  function applyNavCollapsed() {
    var app = document.querySelector('.app');
    if (app && LS.get(LS_NAV) === '1') { app.classList.add('is-nav-collapsed'); }
  }

  function init() {
    applyDensity();
    applyNavCollapsed();
    renderSidebar();
    renderTopbar();
    renderPageHead();
    applyI18n();
    bind();
    document.documentElement.setAttribute('lang', lang === 'cn' ? 'zh-CN' : 'en');
    document.body.dataset.persona = current;
    document.body.dataset.lang = lang;

    if (lang === 'en') {
      setTimeout(function () {
        if (window.QMSUI) {
          QMSUI.toast('info', 'Interface language switched to English',
            'Prototype scope: navigation, page titles and 8D stage labels are bilingual. Business content and field names stay in Chinese — '
            + 'the production system maintains entries via 翻译配置 (requirement 3.17).', 7000);
        }
      }, 500);
    }
  }

  return {
    init: init,
    svg: svg,
    icon: svg,
    can: can,
    t: t,
    persona: persona,
    personaKey: function () { return current; },
    lang: function () { return lang; },
    density: function () { return density; },
    lsGet: LS.get, lsSet: LS.set,
    refresh: function () { renderSidebar(); renderTopbar(); }
  };
})();

document.addEventListener('DOMContentLoaded', function () { QMSShell.init(); });
