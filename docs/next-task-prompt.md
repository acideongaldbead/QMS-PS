# 下一步任务提示词（3.12 系统管理：用户 / 角色 / 权限的规划与开发）

本文件是**开新会话时直接复制粘贴的提示词**，写于 2026-10-15。
项目状态见 `docs/code-inventory.md` 与记忆 `reference_qms_app_workspace.md`；
业务视角的一页说明见 `docs/delivery-status.md`。

> **本次是「先规划、后开发」**：先出一版**角色 / 权限模型 + 界面方案**给用户确认，再动手写代码。
> 2.11 报表与分析的提示词已另存 `docs/next-task-prompt-2.11-reports.md`（KPI 口径未定，先搁置）。

---

```
继续 QMS 生产化项目（问题解决管理系统），本次做 3.12 系统管理 —— 重点是「用户 / 角色 / 权限」的规划与开发。
工作区：C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\
（后端 Spring Boot 3.4.1 / Java 21 / MyBatis-Plus / Flyway；前端 Vite+Vue3+TS+ElementPlus+Pinia；
单端口 8080，前端 dist 打进 jar；远端 origin/main 已同步）

【第一步：先把上下文读进来，不要凭猜测动手】
1. docs\code-inventory.md —— 一页式代码索引（目录、后端模块、前端 views/api、迁移 V1–V21、
   脚本/e2e 清单、各阶段完成度、复用要点与踩坑 1–63）。
2. 记忆文件 ~/.claude/projects/C--Users-Vivien-ma/memory/reference_qms_app_workspace.md
   —— 阶段总览 + 构建链路 + 断言清单 + 迁移编号 + 全部踩坑；另有 reference_qms_git_remote.md（远端与网络）。
3. docs\retrospective.md 第 3 节 —— 全量「现象→根因→处理」问题库（写代码前扫一遍）。
4. 需求与原型：需求正文 ...\ps\qms_prototype\_tools\_out\requirements.txt（搜「3.12」「权限」「系统管理」「3.16」）；
   原型 ...\ps\qms_prototype\admin.html（PS-003 系统管理模块清单）与 assets\js\shell.js（原型里的 PERMS 权限模型）。

【本次范围】需求 3.12「系统管理」的**权限部分**：用户 / 角色 / 权限的可视化配置（角色管理 + 权限分配）。
3.12 原文：「**分级权限**：支持系统级、模块级、功能按钮级、数据行级的精细化权限控制。
**角色管理**：支持预设标准角色（销售质量、质量工程师、审核员、管理员）和按人员/部门自定义角色。
**权限分配**：可按角色分配操作权限（如登记、编辑、删除、审批、查看报表等）。」
（3.12 还含「主数据、系统配置」两项，是否并入本轮见下面的问题。）

**基线 DDL 本就是为此设计的 —— 先读一遍再设计，别新造字段**（`db\migration\V1__baseline.sql`）：
- `employee`：`dept_l1` / `dept_l2`（**注释写明「数据行级权限隔离依据」**）、`line_manager_id`、`is_active`、`synced_at`
- `role`：`role_type`（预设 / 自定义）、**`dept_code`（自定义角色可按部门绑定）**、`is_active`，并已有 `role_code` / `role_name_en`
- `permission`：`permission_level`（**系统级 SYSTEM / 模块级 MODULE / 功能按钮级 BUTTON / 数据行级 ROW**）、`module_code`
- `role_permission`、`user_role` 两张多对多关联表
**现状**：后端只有**只读**接口（`GET /api/master-data/roles`、`/permissions`，需 `rbac:manage`），**没有任何写接口**；
前端 `/admin` 是 `PagePlaceholder` 占位页；`@PreAuthorize` 强制与前端按权限隐藏入口都已就绪；
`user_account` 表（V2）有账号/口令/锁定字段。

【动手前必须先问清的问题（会直接决定表结构与界面，别自己假设）】
- **「数据行级」权限本轮做不做？** 需求 3.12 列了四级、`permission_level` 也有 ROW 值、`dept_l2` 的注释直指
  「数据行级隔离依据」、3.16 还要求「角色 + 数据的细粒度模型、数据隔离」。但**投诉单目前对所有有权限的人可见**
  （「与我相关」只是台账的一个页签口径）。本轮是只做 系统 / 模块 / 按钮 三级、把 ROW 级留到后续，
  还是就要落数据隔离？若做，隔离口径是什么（按 `dept_l2`？复用既有谓词 `complaint_related`？）。
- **自定义角色绑人还是绑部门？** 需求写「按人员/部门自定义角色」，`role.dept_code` 是给部门绑定用的。
  要确认：绑部门时是「该部门所有人自动获得」还是「分配时按部门筛选人」？部门数据从哪来（本机是种子数据，未接 HR）？
- **预设角色的权限能不能改？** 常见做法是预设**只读**，只能「复制为自定义角色」再改；要不要这样？
- **用户 / 账号管理本轮做不做？** 除了「用户角色分配」，是否还要 新增 / 停用账号、重置口令、
  **解锁登录锁定**（登录锁定已实现，但没有解锁入口）？
- **权限变更何时生效？** JWT 里带 permissions、`/auth/me` 每次导航会拉。改完某角色的权限后：
  立即生效（前端重拉）还是要求重新登录？现有 token 要不要主动失效？
- **主数据维护 / 系统配置**本轮是否一并做？（3.12 原话含这两项；主数据现在 9 个 md_type 都是种子，本机无维护入口。）
- 审计口径：3.16 要求「关键数据修改必须留痕、至少 3 年」——权限变更这轮要覆盖哪些动作（建角色 / 改权限 / 停用 / 改人）？

【工作方式（本项目硬要求，请严格遵守）】
1. **先规划再动手**：进计划模式，用探索代理摸清可复用资产（`knowledge`/`report` 的分层样板、
   `MasterDataController` 的只读接口与 `AuthService`/`CurrentUser` 的权限装载、`KnowledgeView` 的
   「列表 + 对话框 + 权限门控」骨架、`AnnouncementManageView` 的状态流转写法与 `RowAction` 图标操作列、
   `verify-knowledge.ps1` + `ui-knowledge.ps1` 的三件套骨架），把**角色/权限模型 + 界面方案 + 要改的后端接口**
   写进计划文件给用户确认后再动手。**阶段边界等指令**，不要自己一路做下去。
2. 后端镜像既有分层：Controller（`@PreAuthorize`，类上 `@RequestMapping("/api")`）
   + Service（`@Transactional` + 审计）+ Mapper（注解 SQL、`<script>` 动态片段、record 投影）
   + `dto/XxxDtos`（record）。**新增 mapper 的 record 必须让 SELECT 列序与组件序一一对齐**（MyBatis 按列位置映射）。
   权限变更后要让 `CurrentUser` 的权限集合能刷新（注意 `JwtAuthFilter` / `AuthService` 现在怎么装载权限）。
3. 每阶段交付必须带：可复跑 API 断言 `verify-xxx.ps1`（**纯 ASCII**，中文期望片段放
   `scripts\_verify_expectations.json`）+ 真机 UI 端到端 `ui-xxx.ps1` + `e2e\xxx.mjs`（截图落 `tools\_out\ui`）
   + 跑既有回归；改完 `.ps1` 必跑 `scripts\_check-ps1-encoding.ps1`。
   整行铺开的页面在 1280 / 1180 两个宽度各截一张核对版式。
4. 构建链路：`frontend-build.ps1` → `backend-build.ps1` → `qms-server.ps1 -Action Start`。
   演示数据走**真实 API** 造（可参考 `tools\_out\seed-knowledge-demo.mjs` 的写法）。
5. 收尾：更新 `docs\code-inventory.md`、`docs\retrospective.md`、`docs\delivery-status.md` 与记忆文件，
   并给用户简洁回执（改了哪些文件、断言数、遗留项）。

【已知约束/坑，别再踩一遍（完整版见 retrospective 第 3 节）】
- `.ps1` 里**一个中文字符都不能有**（连注释也不行），中文只放 `.json` / `.sql` / `.java` / `.mjs`。
- **加权限码要连断言一起改**：V3 的管理员权限是当时的 CROSS JOIN 快照，新增码不会自动落到管理员头上，
  必须在迁移里显式 `INSERT INTO role_permission ... WHERE role_code='ROLE_ADMINISTRATOR'`；
  同时 `verify-masterdata.ps1` 断言了权限总数（当前 **26**），加了要一起改。
- `permission_level` 已有四值（SYSTEM/MODULE/BUTTON/ROW），**别新造枚举**；前端 `auth.can(code)` 是对
  permissions 数组的精确字符串匹配，路由门控用 `meta.permission`；**改了权限后前端要重新拉 `/auth/me`**。
- 表格操作列一律用 `RowAction.vue`（图标 + 悬停浮窗 + `data-act` 钩子），别再写文字按钮。
- PowerShell 5.1 的 `Invoke-RestMethod` 把 JSON 数组当单个对象（`@(...)` 恒为 1 元素 → 断言静默假通过），
  必须先赋值再包 `@()`；`$home` 等保留变量不要用。
- `psql -c` 传中文会失败（SQL 保持 ASCII，或 `-f` 跑 UTF-8 文件）。
- 迁移只追加，V1 基线逐字节冻结；`db-validate-migrations.ps1` 不要用 `2>&1` 调用。
- 前端 UI 脚本的 `data-*` 钩子挂在**自写包装元素**上（Element 会把属性转发到内层 `<input>`）。
- 表格 `fixed="right"` 会渲染两份，脚本点击前过滤 `offsetParent !== null`。
```
