-- ===========================================================================
-- V3 RBAC 结构与种子（追加迁移）
-- ===========================================================================
-- 基线里 role / permission / role_permission / user_role 四张表结构齐全但一行数据
-- 都没有。本迁移补齐前三条的种子；user_role 依赖 employee，放在 V9。
--
-- 同时补两列英文名，供中英文切换（需求 3.17）使用；role_code / permission_code
-- 是应用层引用的稳定标识，不随中文名变动。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE role ADD COLUMN role_code varchar(32) NOT NULL;
ALTER TABLE role ADD COLUMN role_name_en varchar(64);
ALTER TABLE role ADD CONSTRAINT uq_role_code UNIQUE (role_code);
ALTER TABLE role ADD CONSTRAINT uq_role_name UNIQUE (role_name);
COMMENT ON COLUMN role.role_code IS '角色编码 | 应用层引用的稳定标识，如 ROLE_SALES_QUALITY';
COMMENT ON COLUMN role.role_name_en IS '角色英文名 | 供中英文切换';

ALTER TABLE permission ADD COLUMN permission_name_en varchar(64);
ALTER TABLE permission ADD CONSTRAINT uq_permission_code UNIQUE (permission_code);
COMMENT ON COLUMN permission.permission_name_en IS '权限英文名 | 供中英文切换';

-- ---------------------------------------------------------------- 预设角色
-- 需求 3.12 的四个标准角色（Q-04 确认以此为基座，不再增补根因组织角色）。
INSERT INTO role (role_code, role_name, role_name_en, role_type, is_active) VALUES
    ('ROLE_SALES_QUALITY',    '销售质量',   'Sales Quality',    'PRESET', true),
    ('ROLE_QUALITY_ENGINEER', '质量工程师', 'Quality Engineer', 'PRESET', true),
    ('ROLE_AUDITOR',          '审核员',     'Auditor',          'PRESET', true),
    ('ROLE_ADMINISTRATOR',    '管理员',     'Administrator',    'PRESET', true)
ON CONFLICT (role_code) DO NOTHING;

-- ---------------------------------------------------------------- 权限项
-- permission_level：SYSTEM 系统级 / MODULE 模块级 / BUTTON 功能按钮级 / ROW 数据行级
INSERT INTO permission (permission_code, permission_name, permission_name_en, permission_level, module_code) VALUES
    -- 模块级：控制菜单与页面可见性
    ('complaint:view',        '查看投诉',       'View complaints',        'MODULE', 'COMPLAINT'),
    ('report:view',           '查看报告',       'View reports',           'MODULE', 'REPORT'),
    ('analytics:view',        '查看报表',       'View analytics',         'MODULE', 'ANALYTICS'),
    ('knowledge:view',        '查看知识中心',   'View knowledge',         'MODULE', 'KNOWLEDGE'),
    ('masterdata:manage',     '维护主数据',     'Manage master data',     'MODULE', 'MASTERDATA'),
    ('rbac:manage',           '管理角色权限',   'Manage roles',           'MODULE', 'RBAC'),
    ('translation:manage',    '维护翻译配置',   'Manage translations',    'MODULE', 'I18N'),
    ('audit:view',            '查看审计日志',   'View audit log',         'MODULE', 'AUDIT'),
    ('announcement:manage',   '发布系统公告',   'Manage announcements',   'MODULE', 'ANNOUNCEMENT'),
    ('admin.all',             '系统管理',       'System administration',  'MODULE', 'ADMIN'),
    -- 功能按钮级：控制具体动作
    ('complaint:create',      '登记投诉',       'Create complaint',       'BUTTON', 'COMPLAINT'),
    ('complaint:edit',        '编辑投诉',       'Edit complaint',         'BUTTON', 'COMPLAINT'),
    ('complaint:delete',      '删除投诉',       'Delete complaint',       'BUTTON', 'COMPLAINT'),
    ('sample:edit',           '维护样品与物流', 'Edit samples/logistics', 'BUTTON', 'SAMPLES'),
    ('verify:edit',           '录入验证结果',   'Edit verification',      'BUTTON', 'VERIFICATION'),
    ('containment:edit',      '维护遏制措施',   'Edit containment',       'BUTTON', 'CONTAINMENT'),
    ('rootcause:edit',        '维护根因分析',   'Edit root cause',        'BUTTON', 'ROOTCAUSE'),
    ('action:edit',           '维护纠正措施',   'Edit corrective action', 'BUTTON', 'ACTION'),
    ('action:verify',         '验证措施有效性', 'Verify effectiveness',   'BUTTON', 'ACTION'),
    ('prevention:edit',       '维护预防文件',   'Edit prevention files',  'BUTTON', 'PREVENTION'),
    ('report:edit',           '编辑报告',       'Edit report',            'BUTTON', 'REPORT'),
    ('report:generate',       '生成报告',       'Generate report',        'BUTTON', 'REPORT'),
    ('report:export',         '导出报告',       'Export report',          'BUTTON', 'REPORT'),
    ('report:approve',        '审批报告',       'Approve report',         'BUTTON', 'REPORT'),
    ('report:send',           '发送报告给客户', 'Send report',            'BUTTON', 'REPORT')
ON CONFLICT (permission_code) DO NOTHING;

-- ---------------------------------------------------------------- 角色 × 权限
-- 矩阵依据原型 shell.js 的 PERMS 落地，并按 3.12 的职责划分补齐模块级权限。

-- 销售质量：登记与推进投诉、编制与发送报告
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM role r CROSS JOIN permission p
WHERE r.role_code = 'ROLE_SALES_QUALITY'
  AND p.permission_code IN (
      'complaint:view', 'complaint:create', 'complaint:edit',
      'sample:edit', 'report:view', 'report:edit', 'report:generate',
      'report:export', 'report:send', 'analytics:view', 'knowledge:view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 质量工程师：8D 全流程的技术执行者
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM role r CROSS JOIN permission p
WHERE r.role_code = 'ROLE_QUALITY_ENGINEER'
  AND p.permission_code IN (
      'complaint:view', 'complaint:create', 'complaint:edit',
      'sample:edit', 'verify:edit', 'containment:edit', 'rootcause:edit',
      'action:edit', 'action:verify', 'prevention:edit',
      'report:view', 'report:edit', 'report:generate', 'report:export',
      'analytics:view', 'knowledge:view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 审核员：只看和批，不动业务数据
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM role r CROSS JOIN permission p
WHERE r.role_code = 'ROLE_AUDITOR'
  AND p.permission_code IN (
      'complaint:view', 'report:view', 'report:approve',
      'audit:view', 'analytics:view', 'knowledge:view')
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- 管理员：全部权限
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM role r CROSS JOIN permission p
WHERE r.role_code = 'ROLE_ADMINISTRATOR'
ON CONFLICT (role_id, permission_id) DO NOTHING;
