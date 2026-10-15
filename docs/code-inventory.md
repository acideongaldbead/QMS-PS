# QMS 生产系统 — 代码与文件清单（截至 2026-10-14）

本文件是**当前代码库的一页式索引**：目录结构、后端/前端/数据库/脚本清单、8D 各阶段完成度、以及 2.9–2.12 的现状与缺口。面向接手新任务的同事（或下一个会话）快速定位。

> 下一步任务的**开工提示词**在 `docs/next-task-prompt.md`（复制粘贴即用，含「动手前必须先确认的问题」清单）。

---

## 1. 概览

| 项 | 内容 |
|---|---|
| 工程根 | `C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\`（monorepo） |
| 后端 | Spring Boot 3.4.1 / Java 21 / MyBatis-Plus 3.5.9 / Flyway / JJWT；包根 `com.nexperia.qms` |
| 前端 | Vite 6 + Vue 3.5 + TypeScript + Element Plus + Pinia + vue-i18n |
| 数据库 | PostgreSQL 18（本机监听 **5433**），schema `qms`，口令在 `config\.env` |
| 部署形态 | **单端口单进程**：`frontend/dist` 由 pom 打进 jar 的 `static/`，一个 jar 同时提供界面与接口（无 nginx、无 CORS） |
| 关键依赖（已在 pom） | `poi-tl`（Word）、`spring-boot-starter-mail`（D8 邮件）、`tika-core`（附件内容嗅探）、**`jsoup`（公告正文富文本净化）**、`mybatis-plus`、`flyway` |
| 构建链路 | `frontend-build.ps1` → `backend-build.ps1` → `qms-server.ps1 -Action Start` |

> 约定：**迁移只追加**（V1 基线冻结）；**脚本必须落盘为 `.ps1` 再调用**；`.ps1` 保持**纯 ASCII**（中文走 `_verify_expectations.json`）；验收每阶段都要「可复跑断言 + 真机截图」。

---

## 2. 目录结构

```
qms-app/
  .git/ .gitignore  **本地 git 仓库（2026-10-14 建立，分支 main）**。仓库级 `core.autocrlf=false`：
                工作树是混用的行尾（SQL 为 CRLF、Java/TS/PS1 为 LF），而
                `db/migration/V1__baseline.sql` 要与交付 DDL **逐字节一致**，任何行尾转换都会破坏该比对。
                **不要改成 true，也不要加会做行尾归一化的 .gitattributes。**
                `config/.env`（含口令）、`tools/`、`data/`、`logs/`、`run/`、构建产物一律不入库。
  backend/        Spring Boot 模块（下文 §3）
  frontend/       Vite+Vue3 前端（下文 §4）
  db/migration/   Flyway 迁移 V1..V20（下文 §5）
  config/         .env（gitignore，含口令/密钥）+ .env.example + maven-settings.xml（阿里云镜像）
  scripts/        全部 .ps1：构建 / 运维 / 验收 / UI 端到端（下文 §6）
  e2e/            puppeteer-core 驱动脚本（含 node_modules，被 gitignore）（下文 §7）
  docs/           本文件 + docs/reference/（原型 shell.js / mock-data.js 拷贝）
  tools/          jdk-21 / maven / git 绿色版 + _out（构建日志、验收报告、截图）
  logs/ run/      运行日志与 pid
```

---

## 3. 后端清单 `backend/src/main/java/com/nexperia/qms/`

**分层模式**（所有业务模块一致）：`Controller`（`@RestController`，类上 `@RequestMapping("/api")`，方法上 `@PreAuthorize("hasAuthority('...')")`）+ `Service`（`@Service` + `@Transactional` + 审计 + 阶段推进，`requireOpen()` 拦截已结案）+ `Mapper`（`BaseMapper<T>` + `ROW_COLUMNS` 文本块 + `record XxxRow`）+ `dto/XxxDtos`（record）。

| 包 | 关键类 | 说明 |
|---|---|---|
| `QmsApplication` | — | 启动类 |
| `common.security` | `SecurityConfig` `JwtAuthFilter` `JwtService` `CurrentUser` `CurrentUserContext` | JWT 认证；`CurrentUserContext.employeeId()` 供审计/业务取当前人 |
| `common.persistence` | `BaseEntity` `QmsMetaObjectHandler` | 审计列（created_at/by、updated_by）+ `@TableLogic is_deleted` |
| `common.audit` | `AuditLog` `AuditActions` `AuditLogService` | 审计写入；`record/recordValueChange/recordRegardlessOfOutcome`；`AuditActions` 含 CREATE/UPDATE/DELETE/STATUS_CHANGE/**EXPORT/SEND/APPROVE/REJECT** |
| `common.numbering` | `DocumentNumberService` `SequenceMapper` | 单据号：`nextComplaintId`(C…)、`nextReportId`(**R…**)、`nextApprovalId`(AP…) 等 |
| `common.storage` | `StorageService` `LocalFsStorage` `AntivirusScanner`+`Noop`/`ClamAv` `UploadProperties` `FileValidator` | 附件存储 + **可插拔杀毒**（默认 Noop，`qms.antivirus.provider=clamav` 启用） |
| `common.richtext` (**公告管理新增**) | `HtmlSanitizer` | 富文本白名单净化（jsoup `Safelist`）：公告正文写入前过滤，去 `<script>`/事件属性/`javascript:` 链接；文本格式白名单（p/br/strong/b/em/i/u/h1–h4/ul/ol/li/blockquote/a[href]）。`prettyPrint(false)` 保证存盘字节可往返 |
| `common.exception` | `NotFoundException` `GlobalExceptionHandler` `DataIntegrityTranslator` | 异常→HTTP：NotFound 404 / IllegalArgument 400 / **IllegalState 409** / 其余 500 |
| `auth` | `AuthController` `AuthService` `AuthProvider`+`LocalPassword`/`OAuth2` `AuthMapper` | 登录/JWT/锁定；SSO 留空实现 |
| `masterdata` | `MasterDataController` `MasterDataService` | `/api/master-data/*`：字典、失效类型树、客户/发货方/联系人、产品、人员、状态码、角色/权限 |
| `complaint` (D0/D1) | `ComplaintController` `ComplaintService` `SampleController`/`SampleService` `FailureTypeChainValidator` `Complaint` `Sample` `QualityPartner` `ProductInfo` `FailureDescription` + 各 Mapper + `dto/{ComplaintRequests,ComplaintResponses,ComplaintLabels}` `config/PriorityProperties` | 登记/详情/样品；`ComplaintLabels` 提供客户/产品/人名/`contactEmail` 等展示名 |
| `logistics` (2.3) | `ShipmentController` `ShipmentService` `Shipment` `ShipmentSample` `ShipmentStatus` + Mapper | 样品与物流批次 |
| `verification` (D2) | `VerificationController` `VerificationService` `VerificationTask` `VerificationResult` `VerificationTaskStatus` + Mapper | 验证任务/结果录入 + **有效性判定**（`POST /complaints/{id}/validity`，无效即结案） |
| `containment` (D3) | `ContainmentController` `ContainmentService` `ContainmentAction` `ContainmentStatus` + Mapper | 遏制判断（PS-039）+ 措施 |
| `rootcause` (D4) | `RootCauseController` `RootCauseService` `RootCause` `WhyAnalysis` `RootCauseStatus` + Mapper | 根因 + 归属/转交 + 3x5Why/鱼骨图**按版本追加** |
| `actions` (D5/D6/D7) | `ActionsController` `CorrectiveActionService` `PreventionService` `CorrectiveAction` `ActionVerification` `PreventionFileUpdate` `CorrectiveStatus` `PreventionStatus` + Mapper | 纠正措施 CRUD + D6 验证（状态自动派生）+ D7 预防文件 |
| `report` (**D8，本会话新建**) | `ReportController` `ReportService` `ReportContentAssembler` `ReportDocxWriter` **`ReportPdfWriter`** `Report8D` `ReportTeamMember` `ReportDistribution` + `ApprovalTaskMapper` + 3 Mapper + `dto/ReportDtos` + `mail/{ReportMailer,NoopReportMailer,SmtpReportMailer,MailProperties}` | 生成/视图/**Word+PDF 导出**/**提交审批/批准驳回**/发送/结案；组装复用各阶段读方法 |
| `complaintlog` (**遗留清理新建**) | `ComplaintLogController` `ComplaintLogService` `ComplaintLogMapper` + `dto/ComplaintLogDtos` | `GET /api/complaints/{id}/logs`：流程轨迹（`audit_log` 按 `biz_id=投诉号` 跨 biz_type 取）+ 沟通日志（`report_distribution`）合并成一条时间轴，动作/业务码在此翻成中文 |
| `attachment` | `AttachmentController` `AttachmentService` `Attachment` `AttachmentBizType` `FileValidator` + Mapper | 多态附件（`biz_type + biz_id`），含 `Complaint`/`Sample`/`Shipment`/`VerificationTask`/`ContainmentAction`/`RootCause`/`CorrectiveAction`/`PreventionFileUpdate`/`Report8D`。**三道门**：扩展名白名单（`qms.upload.allowed-extensions`，含 Office 全格式）→ Tika 内容类型必须与扩展名匹配 → **OOXML 包内不得有 `vbaProject.bin`**（宏文档拒收） |
| `home` (**2.10 新建**) | `HomeController` `HomeService` `HomeMapper` + `dto/HomeDtos` | `GET /api/home/overview` 一次给全首页：4 个指标 + 待办（按阶段表聚合，读 `status_code.is_final` 判「未完成」，D6 用 `CORR_DONE` 特判）+ 超期横幅（**复用** `ComplaintService.listLedger`）。`countRelatedToMe()` 与台账 `mineTotal` 同一谓词 |
| `announcement` | `AnnouncementController` `AnnouncementService` `Announcement` `AnnouncementMapper` + `dto/AnnouncementDtos` | 公告：**读** `GET /api/announcements?limit=`（只返 `publish_status='已发布'`、`published_at` 倒序、join `employee` 取发布人）+ `POST /{id}/read`（按人已读，NEW 徽标）；**管理**（2.13/公告管理，`announcement:manage`）：`GET/POST /manage`、`GET/PUT /manage/{id}`、`POST /manage/{id}/publish\|retire`、`DELETE /manage/{id}`。正文是**净化后的 HTML**（见 `common.richtext.HtmlSanitizer`），首页抽屉 `v-html` 渲染 |
| `knowledge` (**2.12 新建**) | `KnowledgeController` `KnowledgeService` `KnowledgeArticle` `KnowledgeMapper` + `dto/KnowledgeDtos` | 知识中心（需求 3.11）：`GET /api/knowledge/articles?category=&keyword=` / `GET /api/knowledge/summary` / 单条 GET / POST / PUT / DELETE。列表用 `LEFT JOIN LATERAL` 取**最新附件**（`attachment_id` + 文件名/大小/类型），每行因此能直接显示与下载文件。读 `knowledge:view`、写 `knowledge:manage`。文档文件走通用附件表（`biz_type='KnowledgeArticle'`，`biz_id` = `article_id`） |

**报告模块要点**：`qms.mail.provider` = `noop`（默认，写沟通日志不真发）/ `smtp`（配 `SPRING_MAIL_*` 即真发）；Word 由 POI **代码生成**（仓库无 `XTE-0071.docx`）。

---

## 4. 前端清单 `frontend/src/`

**路由**（`router/index.ts`，hash 模式）：`/login`、`/`(HomeView 工作台)、`/complaints`(LedgerView 台账)、`/complaints/new`、`/complaints/:id`(详情)、`.../report/:reportId`(报告)、`.../report/:reportId/send`(发送，`report:send`)、`/reports`、`/kb`(知识中心，`knowledge:view`)、`/announcements/manage`(公告管理，`announcement:manage`)、`/admin`(`admin.all`)。`meta.permission` 由 `beforeEach` 强制。**（原 `.../root-cause/:rcId/why` 死路由已于 2.12 删除：3x5Why 与鱼骨图在 D4 页签里。）**

| 目录 | 文件 | 状态 |
|---|---|---|
| `views/` | `LoginView` | 完成 |
| | `HomeView` | **完成（2.10）**——4 指标卡 + 系统公告卡（等高左右分栏）+ 超期预警条 + 待办按类型分组（取前 12），点条目跳详情并落到对应页签 |
| | `LedgerView` | **完成（2.9）**——双页签（与我相关/全部数据）+ 简易/高级筛选 + 排序 + 分页 + 列设置 + 批量选择 + 导出 Excel + 复制投诉；`?scope=`/`?q=` 进 URL |
| | `ComplaintCreateView` + `complaint-new/Step*`(5 步向导) | 完成 |
| | `ComplaintDetailView` | 完成（阶段条 + 11 个页签全部接线；**支持 `?tab=` 定位**，首页待办一键跳转到对应阶段） |
| | `Report8DView` `ReportSendView` | 完成（D8） |
| | `KnowledgeView` | **完成（2.12）**——左文档库（按分类分组）+ 右分类筛选（带计数）与维护规则；关键词检索（走服务端）、下载、PDF/图片在线预览；管理员可新建/编辑/软删并上传文档附件。页内把 `.grid-sidebar` 覆盖为「窄右栏」以免筛选栏在 1280 以下被拍成单列 |
| | `AnnouncementManageView` | **完成（公告管理）**——公告列表（状态筛选 全部/草稿/已发布/已下架）+ 新建/编辑对话框（标题、发布时间、**TipTap 富文本正文**）+ 发布/下架/删除；仅 `announcement:manage` 可见，路由同权限门控 |
| | `ReportsView` | **占位**（2.11 未开始） |
| `views/complaint-detail/` | `StageBar` `SamplePanel` `ShipmentPanel` `VerificationPanel`(D2) `ContainmentPanel`(D3) `RootCausePanel`(D4) `WhyMindMap` `FishboneEditor` `CorrectiveActionPanel`(D5) `ActionVerificationPanel`(D6) `PreventionPanel`(D7) `ReportPanel`(D8，含提交审批/审批) **`ComplaintLogPanel`**(沟通与流程日志) | 完成 |
| `components/` | `AttachmentPanel` `FailureTypeCascade` `SampleFields` `QmsIcon` `PagePlaceholder` **`RichTextEditor`(公告管理新，TipTap 懒加载)** | 可复用 |
| `api/` | `http`(axios+`errorMessage`) `complaints`(含 `ledger`/`exportLedger`) `masterData` `attachments`(含 `openInNewTab`) `logistics` `verification` `containment` `rootCause` `actions` `reports` `home` **`knowledge`(2.12 新)** **`announcements`(公告管理新)** | — |
| `stores/` | `auth`(`can(perm)`/`user`) `meta`(字典缓存：含 `fileTypes`、**`knowledgeCategories`(2.12 新)**) | — |
| 其他 | `layouts/AppLayout.vue` `i18n/` `router/` `styles/`（含 `@media print` 与 `.no-print`） | — |

> 前端「行/列布局」注意：`el-form` 的 `label-width` 会级联进 `el-row` 内每个 `el-col`，多列表单行请用 `span=12`×2（D5 已按此修，D3 保留原样）。

---

## 5. 数据库迁移 `db/migration/`（只追加）

| 版本 | 内容 |
|---|---|
| V1 | 交付 DDL **逐字节复制**（45 表 / 91 外键 / 113 索引），UTF-8 无 BOM |
| V2 | `user_account` + `refresh_token` |
| V3 | RBAC：role/permission + 4 角色 / 25 权限 / 58 映射（含 `report:*`） |
| V4 | 8 张带状态外键表的真实状态码 + `name_en`（含 `CORR_*`/`PREV_*`/`STEP_*`/`APPROVAL_*`） |
| V5 | `translation` |
| V6 | `complaint.current_stage`（D0–D8） |
| V7 | `report_section`(jsonb) + `report_team_member` + employee `name_en`/`job_title` |
| V8 | notification 重试字段 |
| V9 | **系统跑起来必需的主数据**（员工/账号/角色/三级失效类型/客户/产品/生产/TPT/公告） |
| V10 | 物流状态码登记进 `status_code` |
| V11 | `current_stage` 默认 D1 |
| V12 | `uq_shipment_sample` → 部分唯一索引（软删除可重加） |
| V13 | D2 验证状态码 + 结案原因（`CLOSE_NORMAL/INVALID/TRANSFERRED`） |
| V14 | 修正 `ck_complaint_dates`（`close_date >= created_at::date`） |
| V15 | `complaint.containment_required` / `containment_decision_note`（PS-039） |
| V16 | `containment_action.planned_completion_date` |
| V17 | **`complaint_related(complaint_id, employee_id)` 函数**（**2.9 新增**）：「与我相关」判定一处定义——主表 4 个责任人 + 发起人 + 7 张阶段子表 owner。台账列表/双页签计数/首页「与我相关投诉」都调它。**函数内表名写全 `qms.` 前缀**（SQL 函数会被内联进调用方查询，用的是调用方的 search_path） |
| V18 | **`announcement_read(announcement_id, employee_id)`**（遗留清理新增）：公告「NEW」按人未读的依据，点击一次写一行（`ON CONFLICT DO NOTHING` 幂等）。**报告审批没有新表**——基线的 `approval_task` 与 `APPROVAL_*` 状态码本就是为此预留 |
| V19 | **`attachment.file_type` 由 `varchar(32)` 放宽到 `varchar(128)`**：OOXML 的 MIME 类型长达 64–73 字符，docx/xlsx 原为「宣称支持、实际必挂」且报错与真实原因无关（详见 `retrospective.md` §3.7-8） |
| V20 | **知识中心（2.12）**：`knowledge_article` 加 `doc_code` / `title_en` / `version` / `summary`；文档编号**部分唯一索引**（`WHERE is_deleted = false AND doc_code IS NOT NULL`，软删不占号）；种 4 条 `knowledge_category` 字典（流程文件 / 分析模板 / 培训教材 / 操作手册）；种权限码 `knowledge:manage` 并**显式**映射给管理员（V3 的管理员权限是当时的 CROSS JOIN 快照，新码不会自动获得） |
| V21 | **公告正文改富文本（公告管理）**：纯数据迁移，无 schema 变更（`content` 自 V1 起就是 `text`）。把 V9 种的 3 条纯文本公告包成 `<p>`（**幂等**：只在 `content NOT LIKE '<%'` 时改写；`&`→`&amp;` 先于 `<`/`>` 转义）。净化不在迁移做，在应用写入侧（`HtmlSanitizer`） |

> 与 D8 相关的表均在 **V1 基线**：`report_8d`（报告头 + 三日期 + `approval_status` + `template_code`）、`report_step_owner`、`report_distribution`（= 沟通日志）、`approval_task`（通用审批，未接线）。

---

## 6. 脚本清单 `scripts/`（全部 `.ps1`）

**构建/运维**：`setup-local-toolchain` `env` `db-create` `db-check` `db-validate-migrations` `sync-baseline-ddl` `sync-prototype-assets` `frontend-install` `frontend-build` `backend-build` `qms-server`(`Start|Stop|Status|Restart`) `list-accounts` `db-clear-complaints` `_check-ps1-encoding` `_shot` `_probe-downloads`。

**验收（API，自清理）**：`verify-auth` `verify-masterdata` **`verify-complaint`(53 项，含流程日志)** **`verify-attachment`(40 项，含 Office 全格式/宏拒收)** `verify-antivirus` `verify-logistics` `verify-verification`(D2) `verify-containment`(D3) `verify-rootcause`(D4) **`verify-actions`(D5/D6/D7，57 项)** **`verify-report`(D8，60 项，含审批链与 PDF)** **`verify-ledger`(2.9，54 项)** **`verify-home`(2.10，43→44 项，含公告已读与正文为 HTML)** **`verify-knowledge`(2.12，68 项)** **`verify-announcement`(公告管理，64 项)**。

**UI 端到端（真机 + 截图落 `tools/_out/ui`）**：`ui-capture` `ui-wizard` `ui-logistics` `ui-d2` `ui-d3` `ui-d4` `ui-d5` `ui-d6` `ui-d7` **`ui-d8`(18 项，三角色走完审批链)** `ui-lazyload` **`ui-ledger`(20 项)** **`ui-home`(26 项，含 NEW 标识与 1280/1180 两次布局核对)** **`ui-knowledge`(2.12，34 项，含 1280/1180 版式核对与管理员/读者双角色)** **`ui-announcement`(公告管理，17 项，管理员发布 + 首页抽屉渲染 HTML + 工程师无入口)**。

**种子**：`seed-demo-showcase.ps1`——建一张走完 **D0–D8** 的展示单（含已生成的报告），打印详情页与报告页 URL（演示用，**不清理**）。**`seed-demo-ledger.ps1`**（**2.9 新增**）——走真实 API 造 40 张演示投诉（覆盖 9 个阶段、~20% 超期、4 张正常结案、4 张投诉不成立；每 3 张里 1 张「属于 U04」，让双页签与首页待办都有内容），最后回填 `created_at` 使「处理天数」非 0；文案在 `_seed_ledger_text.json`。**用前先 `db-clear-complaints.ps1 -Force`**（只增不删）。

**公共数据**：`_paths.json`（路径集中配置）、`_verify_expectations.json`（验收脚本里的**中文期望片段**）。

---

## 7. e2e 清单 `e2e/`（puppeteer-core → 本机 Edge，不下载 Chromium）

`capture.mjs`（多角色登录截图）、`wizard.mjs`（登记向导）、`detail.mjs`、`d2.mjs` `d3.mjs` `d4.mjs` `d5.mjs` `d6.mjs` `d7.mjs` `d8.mjs`（各阶段页签端到端）、**`ledger.mjs`** **`home.mjs`**、`lazy-load.mjs`（按需加载实测）、`fake-clamd.mjs`（模拟 clamd 守护进程）。

调用方式：每个 `ui-dN.ps1` 负责**建数据 + 找 Edge + 跑对应 `dN.mjs` + 清理**；浏览器逻辑在 `.mjs` 里。

---

## 8. 功能完成度与断言（8D 各阶段 + 横向能力）

| 阶段 | 后端 | 前端 | API 断言 | UI 断言 |
|---|---|---|---|---|
| D0/D1 登记 + 团队 | ✅ | ✅ 向导/详情 | `verify-complaint` 53 | `ui-wizard` |
| 样品与物流 | ✅ | ✅ | `verify-logistics` 50 | `ui-logistics` 9 |
| D2 验证与问题定义 | ✅ | ✅ | `verify-verification` 76 | `ui-d2` 16 |
| D3 遏制措施 | ✅ | ✅ | `verify-containment` 55 | `ui-d3` 11 |
| D4 根因分析 | ✅ | ✅ | `verify-rootcause` 54 | `ui-d4` 11 |
| D5 纠正措施 | ✅ | ✅ | `verify-actions` 57（含 D6/D7） | `ui-d5` 6 |
| D6 措施实施与验证 | ✅ | ✅ | 同上（D6 段） | `ui-d6` 7 |
| D7 预防再发生 | ✅ | ✅ | 同上（D7 段） | `ui-d7` 6 |
| **D8 报告与结案** | ✅ | ✅ | `verify-report` 60 | `ui-d8` 18 |
| 附件中心 | ✅ | ✅ | `verify-attachment` 40 / `verify-antivirus` 17 | UI 上传验证 |
| **知识中心 3.11（2.12）** | ✅ | ✅ | `verify-knowledge` 68 | `ui-knowledge` 34 |
| **公告管理（PS-003，公告富文本）** | ✅ | ✅ | `verify-announcement` 64（+ `verify-home` 44） | `ui-announcement` 17 |

> **合计（2026-10-15 实测，全绿）**：API 验收 **738 项**（15 个 `verify-*.ps1`）；
> UI 端到端 **203 项**（15 个 `ui-*.ps1` / `e2e\*.mjs`，另有 `ui-capture` 5 角色菜单截图）。
> 逐脚本清单见 §6。

---

## 9. 2.9–2.12 现状与缺口（下一步主要战场）

需求对应：**3.0 首页工作台**（我的待办 + 系统公告）、**3.10 报表与分析**、**3.11 知识中心**；台账见「问题解决台账」章节。

| 项 | 现状 | 关键缺口 |
|---|---|---|
| **2.9 问题解决台账（双页签）** | **完成** | 双页签确认=「与我相关 / 全部数据」；`GET /api/complaints`（分页/筛选/排序，排序白名单在 mapper 的 `<choose>`）+ `GET /api/complaints/export`（xlsx）；「与我相关」最宽口径（4 责任人+发起人+阶段任务 owner）；API 54 项 + UI 20 项 |
| **2.10 首页工作台** | **完成** | `GET /api/home/overview`（指标+待办+超期横幅，待办从阶段表按 `is_final` 聚合）+ `GET /api/announcements`；详情页支持 `?tab=` 定位；API 43 项 + UI 26 项 |
| **2.11 报表与分析** | `ReportsView.vue` = 占位 | 后端零；需求 3.10（8D 状态统计 + 3 个 KPI + TPT 分析 + 自定义报表/导出） |
| **公告管理（PS-003，公告富文本）** | **完成** | 需求 3.0 的公告从「只读、纯文本」补成完整管理：`announcement:manage` 后台页（新增/编辑/发布/下架/软删）+ 正文改**富文本**（TipTap 编辑器 + jsoup 白名单净化 + 首页抽屉 `v-html`）；V21 把历史纯文本公告转成 HTML。API 64 项 + UI 17 项 |
| **2.12 知识中心** | **完成** | 需求 3.11：`knowledge_article` 扩 4 列 + `knowledge_category` 字典 + `knowledge:manage`（V20）；后端 `knowledge` 模块；前端文档库（分类分组 / 筛选计数 / 关键词检索 / 下载 / PDF·图片预览 / 管理员维护 + 附件）。API 68 项 + UI 34 项。**经验分享（标签/订阅/模糊检索）按需求 1.5 一期排除** |

**2.9/2.10 刻意偏离原型的四处**（交付时须说明）：① 公告无「置顶」徽标（`system_announcement` 无置顶列）；② 公告抽屉无附件；③ ~~待审批报告尚未单列~~ **已于 2026-10-14 遗留清理中接线**（`report_8d.approval_status` = DRAFT/PENDING/APPROVED/REJECTED，`approval_task` 记录审批人，「待审批报告」按**审批人**归属）；④ 台账「流程类型」列与筛选**已删**——`complaint.process_type` 恒为 `'8D'`，原型那四个中文字流类型在真实系统无数据支撑。

**遗留清理（2026-10-14 用户下令，全部完成）**：公告 NEW 按人未读（V18 + `announcement_read`）；详情页「沟通与流程日志」页签（`complaintlog` 模块）；**报告审批接线并卡住发送**；8D 报告 **PDF 导出**（PDFBox + 内嵌系统中文字体）。**仍未做**：2.11 报表与分析。

**同日按业务口径收口（均为刻意设计，不要当成缺陷改回去）**：附件放行 Office 全格式并**拒收宏文档**（V19 修 `file_type` 列宽，详见 §10-47/48）；**不做「客户版/内部版」双版本**；8D 报告 D7/D8 以 **XTE-0071 模板**为准（模板存 `docs/templates/XTE-0071.docx`），尾部为 D7 → Read-across → D8 TEAM RECOGNITION → SIGN-OFF AND DISTRIBUTION；**报告抬头沿用样例的 15 项**（模板只有 5 项，`Diffusion Process` 无对应字段属已知）；**D1 用业务角色名**（不改模板的 Team Leader/Team Member）；**Read-across 与 Team Recognition 不由系统填写**（业务确认，打印模板原文即为最终形态）；投诉编号为 **C+4 位年+5 位序号**。

**另有零散遗留**：**2.11 报表与分析仍是占位页**（`ReportsView.vue`，后端零）；`/admin` 系统管理页是占位页——需求 **3.12 权限管理**只有后端 RBAC 强制 + 只读接口，没有管理界面；**3.13 通知与提醒**（TPT 提醒 / 飞书）与 **3.14 系统集成**未实现（主数据为本机种子，未接 SAP/PLM/MDM/MES）。

**可复用资产**：`actions/*`、`report/*`、**`knowledge/*`**（分层样板）；`stores/meta.ts`（字典，如 `fileTypes`/`knowledgeCategories`）；`api/*.ts`；`AttachmentPanel`/`Blob 下载`/`@media print`；`auth.can(perm)`（权限码 `complaint:view`/`report:view`/`analytics:view`/`knowledge:view`/`knowledge:manage`）；验收脚本骨架（`verify-knowledge` 是「列表 + 字典 + 附件」三件套的最新样板，`ui-knowledge` 是双角色 + 两宽度版式核对的最新样板）；`seed-demo-showcase.ps1`。

---

## 10. 复用要点与已踩的坑（写新功能前先扫一眼）

> 本节是**最常踩的速查**。完整版（**复盘 + 每条坑的现象 / 根因 / 处理**，按主题分组）在
> `docs/retrospective.md`；那里的「1.2 做对了什么 / 1.4 关键决策与放弃了什么」也值得先读。

1. `.ps1` 纯 ASCII，中文只放 `_verify_expectations.json`（PS5.1 按 GBK 解码无 BOM 文件）；`psql -c` 传中文会失败 → SQL 用 ASCII。
2. 请求路径**别漏 `/api` 前缀**（漏了会落到静态资源处理器，表现为 500）。
3. `el-form label-width` 级联进 `el-row` 窄列 → 多列行用 `span=12`×2。
4. MyBatis 用构造器映射 record：**每个构造参数都要能对上列**；jsonb 列不要用 String 直接写。
   **补（2.10 踩到）**：匹配是**按列顺序**的，不只是「有这一列」。`AnnouncementView` 里我把 `publishedByName` 写在 `publishedAt` 前面，而 SELECT 顺序相反，结果 `published_at`（timestamptz）被喂给 String 参数 → 驱动报 `Cannot convert VARCHAR to OffsetDateTime` → 500。**新增 mapper 的 record 时，让 SELECT 列序与组件序逐一对齐**（两处都加注释互相指认）。
5. 软删除 + 普通唯一约束会让「移除后加不回来」→ 用**部分唯一索引** `WHERE is_deleted = false`。
6. 审计：业务动作随事务；**被拒绝/失败的审计要独立事务**（`recordRegardlessOfOutcome`）。
7. 阶段推进只前进不回退；`advanceComplaint` 需同时比较 stage 与 status 序号。
8. 浏览器 e2e：点击按 `offsetParent !== null` 过滤（Element 固定列会渲染两份）；按 label 找输入需**两侧归一化**。
   **补（2.10）**：① `page.goto()` 只改 `#hash` 时**不会重挂组件**，所以「先深链再测默认页签」会量到上次的 `?tab=`——基准要在深链之前量；② 用「共 N 条记录」这类**服务端给的文字**断言行数，别数 DOM 行（固定列/虚拟滚动都会骗人）；③ 排序断言别用只有两行且首列为默认序的列（Element 首次点击是升序，常与默认序相同）——换成默认序不同的列，或比对整列顺序。
9. **SQL 函数内表名要写全 `qms.` 前缀**（2.9 的 `complaint_related`）。SQL 语言函数会被**内联**进调用方查询，内联后用的是**调用方会话**的 search_path；应用连接设了，但手工 psql / 运维查询没有 → 会报「关系 complaint 不存在」。函数级 `SET search_path` 能修，但会**阻止内联**（失去性能）。另：V17 已在本地应用后又改了内容，需 `DELETE FROM qms.flyway_schema_history WHERE version='17'` 让 Flyway 重新应用。
10. **演示数据要走真实 API 造**：`current_stage` 与 `status_code` 的对应关系（7 个状态 ≠ 9 个阶段，且 D2 有两条分支）只有应用自己推进才自洽，手写 INSERT 迟早造出界面渲染不出的状态。代价：`created_at` 由应用写死为 now() → 「处理天数」全是 0，需在最后用 psql 回填（`created_at = start_date - 7`）。
11. **应用自身的业务校验会挡住「看起来合理」的演示数据**：`目标日期不能早于开始日期`、`任务目标完成日不能早于计划开始日`。造数据时先想一遍这些规则（本次连踩两次）。
12. **演示数据的「责任人池」必须刻意让出差异**（原型早就写了这条，我又踩了一次）：只要 owner/协调人/验证负责人池里包含演示登录账号，`complaint_related` 就会命中几乎所有单据，双页签退化成同一个集合。现在的做法是**每 3 张里挑 1 张明确「属于 U04」**，其余完全不含 U04，并让 D2-D7 的推进由两个工程师交替执行。
13. **PowerShell 5.1 的 `Invoke-RestMethod` 把 JSON 数组当作「单个对象」写进管道**，所以 `@(Invoke-RestMethod ...)` 得到的是**1 个元素**（其属性是数组），`.Count` 恒为 1、`$_` 变成整个集合——断言会「静默地」永远成立。**先赋值再包 `@()`**：`$r = Invoke-RestMethod ...; @($r | Where-Object {...}).Count`。（同一个 `$r` 若来自 `(Api ...).body` 这种属性取值则没有此问题。）
14. **PDF 里写中文必须内嵌 CJK 字体**：PDF 内置字体渲染中文会得到空白/方框。用 PDFBox 的 `PDType0Font.load` + 系统黑体（`simhei.ttf`，单个 TTF；`.ttc` 字体集合要先取 face，本实现直接拒绝并提示），字体路径走 `qms.report.pdf-font` 配置、缺失时明确报错而不是产出空白文件。字数不多时**只嵌入用到的子集**，一份报告约 14KB。
15. **审批这类「闸门」必须连脚本、种子、UI 一起改，否则等于把既有验收打断**：给报告发送加审批前置时，会走到发送的四处都要同步——`verify-report.ps1`（补提交/审批与闸门断言）、`ui-d8.ps1`+`d8.mjs`（改成工程师→审批人→销售三角色）、`seed-demo-showcase.ps1`、`seed-demo-ledger.ps1`（发送前先提交+批准）。**改动被既有验收覆盖的行为时，先 grep 谁会走到那条路径**（如 `/send`、`/r…/reports`），一次改齐再跑全量回归。
16. **`AttachmentController.MAY_ATTACH` 是一张扁平白名单，光靠它等于没做细粒度鉴权**（2.12 写断言时暴露）：它是 `hasAnyAuthority` 把**所有** `*:edit` 码并列，所以**持有任一编辑权限的人可以往任意类型挂附件** —— 实测「只有 `rootcause:edit` 的质量工程师」能把文件传进知识文档，直接架空「知识中心只由 `knowledge:manage` 维护」。对策：`AttachmentBizType.WRITE_PERMISSIONS` 把每种 `biz_type` 映射到它自己的编辑权限，由 `AttachmentService.requireWritePermission` 在 upload/delete 里裁决（放在 `requireSupportedBiz` 之后，未知类型仍回 400；放在父存在性检查之前，未授权者无法拿它探测 id）。**只加常量不够，权限是第二道。**
17. **`countParent` 里 `knowledge_article` 是第一个 bigint 父主键**，其余 9 类都是 varchar 业务号。写 `article_id = #{bizId}` 会报 `operator does not exist: bigint = character varying`；写 `CAST(#{bizId} AS bigint)` 则让**非法 id 抛异常变 500**。用 **`article_id::text = #{bizId}`**：任何输入都安全地返回 0 → 404（表很小，不依赖索引）。
18. **Element Plus 的 `el-input` / `el-select` 会把 fallthrough 属性转发到内层控件**，所以 UI 脚本把 `data-*` 钩子挂在组件上时，`[data-x] input` 这类后代选择器**匹配不到**（属性其实落在 `<input>` 上）。对策：把钩子挂在自己写的包装元素上（本项目用 `<div class="kb-field" data-kb-field-xxx>`），选择器才是确定的。
19. **V3 种管理员权限用的是当时的 `CROSS JOIN` 全量快照**，所以**任何后加的权限码都不会自动落到管理员头上**，必须在新增迁移里显式补一条 `role_permission`（V20 的 `knowledge:manage` 就是这么做的，并在迁移里写了注释）。同时：**加权限码会让断言「权限总数」的脚本失败** —— `verify-masterdata.ps1` 有一条 `administrator sees 25 permissions`，本轮会同改成 26。
20. **`db-validate-migrations.ps1` 不要用 `2>&1` 调用**：它内部 `dropdb --if-exists` 在没有临时库时会把一行中文提示写到 stderr，而脚本顶层是 `$ErrorActionPreference='Stop'`，于是**脚本在第一条迁移之前就中止**（表现为「校验失败」而其实什么都没跑）。直接调用正常。这与第 1 条坑同源。
21. **Spring Boot 3.4.1 的父 POM 并不管理 `org.jsoup:jsoup` 的版本**（它管 `tika`、`pdfbox` 等，但 jsoup 要从 BOM 外自己钉）。`<dependency>` 不写 `<version>` 会在**读 POM 阶段**就报 `'dependencies.dependency.version' ... is missing`。加 jsoup 时要配 `${jsoup.version}`。**教训：别假设「Spring Boot 管所有常见依赖的版本」，第一次构建就会告诉你。**
22. **`$home` 是 PowerShell 的保留自动变量**（= 用户主目录），脚本里 `$home = ...` 会抛 `VariableNotWritable` 而**不终止**（`$ErrorActionPreference='Continue'`），于是 `$home` 仍是主目录字符串，`@($home | Where-Object {...})` 的断言**静默假成立/假失败**（本轮两条首页公告断言就是这样被歪掉的）。给列表变量起名避开 `$home`/`$input`/`$args` 等保留名（用 `$homeList`）。
23. **富文本正文用 `v-html` 渲染时**：① scoped 样式**不作用于 `v-html` 子节点**，块级样式要写 `.ann-body :deep(p){}`；② 旧的 `white-space: pre-wrap` 必须去掉（否则每个标签边界多一个空行）；③ 写入侧必须净化（`HtmlSanitizer`），读取侧**不要**再洗一遍，否则列序/引号被规范化、字节往返断言必挂。另：`Safelist` 里漏掉 `<p>` 会让 TipTap 的每个段落存成空。

> 相关记忆文件：`~/.claude/projects/C--Users-Vivien-ma/memory/reference_qms_app_workspace.md`（阶段进度、脚本清单、全部踩坑、D5–D8 设计决策）。
