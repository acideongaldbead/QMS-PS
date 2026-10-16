# QMS 问题解决管理系统 · 文件地址索引

**用途**：一页列出系统的全部文件位置，便于导航、交接与备份核对。
**与其它文档的分工**：本文件只回答「文件在哪」；「代码怎么组织、各阶段做到哪」「踩过哪些坑」看 [`code-inventory.md`](code-inventory.md)，业务视角的进度看 [`delivery-status.md`](delivery-status.md)，复盘看 [`retrospective.md`](retrospective.md)。

**日期**：2026-10-16

---

## 一、根目录

```
C:\Users\Vivien.ma\Documents\Vivien\ps\
├─ qms-app\            生产系统（后端 + 前端 + 迁移 + 脚本 + 文档）—— 绝大部分文件在这
├─ qms_prototype\      需求原型（纯 HTML，双击即看）
├─ qms_backlog_update\ 需求 / Backlog 工作簿与转换工具
├─ QMS-问题解决管理系统-PostgreSQL-DDL.sql   交付 DDL（152,758 字节；V1 基线的来源）
├─ QMS-问题解决管理系统-Product-Backlog.xlsx  Backlog 工作簿
└─ QMS-问题解决管理系统-数据字典与ER设计.xlsx  数据字典与 ER 设计
```

---

## 二、`qms-app\` —— 生产系统

### 2.1 顶层

```
qms-app\
├─ backend\        Spring Boot 3.4.1 / Java 21 / MyBatis-Plus / Flyway
├─ frontend\       Vite 6 + Vue 3.5 + TypeScript + Element Plus + Pinia
├─ db\migration\   Flyway 迁移 V1–V22（只追加）
├─ scripts\        全部 .ps1（构建 / 运维 / 验收 / UI 端到端）
├─ e2e\            puppeteer-core 驱动脚本（浏览器侧逻辑）
├─ docs\           代码索引 / 复盘 / 交付状态 / 本文件 / 模板 / 原型参考
├─ deploy\         生产部署方案与配置模板
├─ config\         .env（口令，不入库）、.env.example、maven-settings.xml
├─ .gitignore      .github\（空目录）
└─ tools\ data\ logs\ run\   ← 工具链 / 附件 / 日志 / pid，全部不入库
```

### 2.2 后端 `qms-app\backend\`

```
pom.xml                                   Maven 构建（产物 target\qms-api.jar，不入库）
src\main\resources\                       application.yml / application-local.yml / logback-spring.xml
src\main\java\com\nexperia\qms\           根包，按业务域分包 ↓
```

| 包 | 内容 |
|---|---|
| （根） | `QmsApplication.java` |
| `common\audit` | `AuditActions` `AuditLog` `AuditLogService` `mapper\AuditLogMapper` |
| `common\security` | `SecurityConfig` `JwtAuthFilter` `JwtService` `CurrentUser` `CurrentUserContext` `PermissionCache` `PasswordPolicy` |
| `common\persistence` | `BaseEntity` `QmsMetaObjectHandler` `MybatisPlusConfig` |
| `common\exception` | `GlobalExceptionHandler` `DataIntegrityTranslator` `NotFoundException` |
| `common\numbering` | `DocumentNumberService` `mapper\SequenceMapper` |
| `common\storage` | `StorageService` `LocalFsStorage` `FileValidator` `AntivirusScanner` `ClamAvScanner` `NoopAntivirusScanner` `UploadProperties` |
| `common\richtext` | `HtmlSanitizer` |
| `auth` | `AuthController` `AuthService` `AuthProvider` `LocalPasswordAuthProvider` `OAuth2AuthProvider` `LocalPasswordInitializer` **`AdminPasswordCli`** `UserAccount` `EmployeeProfile` `AccountAuthState`、`dto\(LoginRequest / LoginResult / MeResponse / ChangePasswordRequest)`、`mapper\AuthMapper` |
| `admin` | `AdminUserController` `AdminUserService` `AdminRoleController` `AdminRoleService` `AdminPermissionController` `MatrixExcelWriter`、`dto\AdminDtos`、`mapper\AdminMapper` |
| `masterdata` | `MasterDataController` `MasterDataService` `MasterDataAdminController` `MasterDataAdminService`、`dto\(MasterDataDtos / MasterDataAdminDtos)`、`mapper\(MasterDataMapper / MasterDataAdminMapper)` |
| `complaint`（D0/D1） | `Complaint` `Sample` `QualityPartner` `ProductInfo` `FailureDescription` `ComplaintController` `ComplaintService` `SampleController` `SampleService` `SampleSupport` `FailureTypeChainValidator` `LedgerExcelWriter`、`config\PriorityProperties`、`dto\(ComplaintRequests / ComplaintResponses / ComplaintLabels)`、`mapper\(Complaint / Sample / QualityPartner / ProductInfo / FailureDescription / Reference)` |
| `logistics`（D2.3） | `Shipment` `ShipmentSample` `ShipmentStatus` `ShipmentController` `ShipmentService`、`dto\LogisticsDtos`、`mapper\(ShipmentMapper / ShipmentSampleMapper)` |
| `verification`（D2） | `VerificationTask` `VerificationResult` `VerificationTaskStatus` `VerificationController` `VerificationService`、`dto\VerificationDtos`、`mapper\(VerificationTaskMapper / VerificationResultMapper)` |
| `containment`（D3） | `ContainmentAction` `ContainmentStatus` `ContainmentController` `ContainmentService`、`dto\ContainmentDtos`、`mapper\ContainmentActionMapper` |
| `rootcause`（D4） | `RootCause` `WhyAnalysis` `RootCauseStatus` `RootCauseController` `RootCauseService`、`dto\RootCauseDtos`、`mapper\(RootCauseMapper / WhyAnalysisMapper)` |
| `actions`（D5/D6/D7） | `CorrectiveAction` `ActionVerification` `PreventionFileUpdate` `CorrectiveStatus` `PreventionStatus` `ActionsController` `CorrectiveActionService` `PreventionService`、`dto\ActionDtos`、`mapper\(CorrectiveActionMapper / ActionVerificationMapper / PreventionFileUpdateMapper)` |
| `report`（D8） | `Report8D` `ReportTeamMember` `ReportDistribution` `ReportController` `ReportService` `ReportContentAssembler` `ReportDocxWriter` `ReportPdfWriter`、`dto\ReportDtos`、`mail\(ReportMailer / NoopReportMailer / SmtpReportMailer / MailProperties)`、`mapper\(ReportMapper / ReportTeamMemberMapper / ReportDistributionMapper / ApprovalTaskMapper)` |
| `attachment` | `Attachment` `AttachmentBizType` `AttachmentController` `AttachmentService`、`dto\AttachmentDtos`、`mapper\AttachmentMapper` |
| `complaintlog` | `ComplaintLogController` `ComplaintLogService`、`dto\ComplaintLogDtos`、`mapper\ComplaintLogMapper` |
| `home` | `HomeController` `HomeService`、`dto\HomeDtos`、`mapper\HomeMapper` |
| `announcement` | `Announcement` `AnnouncementController` `AnnouncementService`、`dto\AnnouncementDtos`、`mapper\AnnouncementMapper` |
| `knowledge` | `KnowledgeArticle` `KnowledgeController` `KnowledgeService`、`dto\KnowledgeDtos`、`mapper\KnowledgeMapper` |

> 后端**没有 `src\test`**：验收全部走 `scripts\verify-*.ps1`（对着真实服务跑）。

### 2.3 前端 `qms-app\frontend\`

```
index.html  vite.config.ts  tsconfig.json  package.json  package-lock.json
（node_modules\ 与 dist\ 不入库）
src\
├─ main.ts  App.vue  env.d.ts
├─ api\        http.ts  complaints.ts  logistics.ts  verification.ts  containment.ts
│              rootCause.ts  actions.ts  reports.ts  home.ts  knowledge.ts
│              announcements.ts  masterData.ts  masterDataAdmin.ts  admin.ts
├─ stores\     auth.ts  meta.ts  ui.ts
├─ router\     index.ts
├─ layouts\    AppLayout.vue
├─ i18n\       index.ts  locales\(zh-CN.ts / en-US.ts)
├─ styles\     tokens.css  base.css  components.css  element-bridge.css
├─ components\ AttachmentPanel  DocumentPreviewDialog  FailureTypeCascade  PagePlaceholder
│              QmsIcon  RichTextEditor  RowAction  SampleFields
└─ views\
   ├─ LoginView  HomeView  LedgerView  ComplaintCreateView  ComplaintDetailView
   │  ReportsView  Report8DView  ReportSendView  KnowledgeView  AnnouncementManageView
   │  AdminView  ChangePasswordView
   ├─ admin\             MasterDataPanel.vue  FailureTypePanel.vue
   ├─ complaint-new\     StepHeader  StepQualityPartner  StepProduct  StepFailureDescription
   │                     StepSamples  types.ts
   └─ complaint-detail\  StageBar  SamplePanel  ShipmentPanel  VerificationPanel
                         ContainmentPanel  RootCausePanel  WhyMindMap  FishboneEditor
                         CorrectiveActionPanel  ActionVerificationPanel  PreventionPanel
                         ReportPanel  ComplaintLogPanel
```

### 2.4 数据库迁移 `qms-app\db\migration\`（22 个，只追加）

```
V1__baseline.sql（逐字节冻结，勿改）   V2__auth.sql                V3__rbac.sql
V4__status_lookup_seed.sql             V5__translation.sql         V6__complaint_stage.sql
V7__report_section_and_people.sql      V8__notification_retry.sql  V9__master_data.sql
V10__shipment_status_seed.sql          V11__complaint_stage_default.sql
V12__shipment_sample_unique.sql        V13__d2_verification_lookup.sql
V14__complaint_close_date_check.sql    V15__containment_decision.sql
V16__containment_planned_date.sql      V17__complaint_related.sql
V18__announcement_read.sql             V19__attachment_file_type_width.sql
V20__knowledge_center.sql              V21__announcement_rich_text.sql
V22__rbac_admin.sql
```

### 2.5 脚本 `qms-app\scripts\`（50 个 .ps1 + 5 个配置/数据文件）

```
构建 / 运维
  setup-local-toolchain.ps1   env.ps1            db-create.ps1        db-check.ps1
  db-validate-migrations.ps1  sync-baseline-ddl.ps1                  sync-prototype-assets.ps1
  frontend-install.ps1        frontend-build.ps1  backend-build.ps1    qms-server.ps1
  list-accounts.ps1           db-clear-complaints.ps1

演示数据
  seed-demo-ledger.ps1        seed-demo-showcase.ps1

API 验收（括号内为断言条数；全部自清理）
  verify-auth.ps1(21)             verify-masterdata.ps1(25)        verify-complaint.ps1(53)
  verify-attachment.ps1(40)       verify-antivirus.ps1(17)         verify-logistics.ps1(50)
  verify-verification.ps1(76)     verify-containment.ps1(55)       verify-rootcause.ps1(54)
  verify-actions.ps1(57)          verify-report.ps1(60)            verify-ledger.ps1(54)
  verify-home.ps1(44)             verify-knowledge.ps1(68)         verify-announcement.ps1(64)
  verify-admin.ps1(72)            verify-masterdata-manage.ps1(63)

真机 UI 端到端（截图与报告落 tools\_out\ui\）
  ui-capture.ps1  ui-wizard.ps1  ui-logistics.ps1  ui-d2.ps1  ui-d3.ps1  ui-d4.ps1
  ui-d5.ps1  ui-d6.ps1  ui-d7.ps1  ui-d8.ps1  ui-lazyload.ps1  ui-ledger.ps1
  ui-home.ps1  ui-knowledge.ps1  ui-announcement.ps1  ui-admin.ps1(39)  ui-masterdata.ps1(34)

内部工具与公共数据
  _check-ps1-encoding.ps1（守卫：.ps1 必须纯 ASCII 或带 BOM）
  _shot.ps1  _probe-downloads.ps1
  _paths.json（全部路径集中配置）  _verify_expectations.json（验收脚本里的中文期望片段）
  _seed_ledger_text.json
```

### 2.6 浏览器端到端 `qms-app\e2e\`

```
capture.mjs  wizard.mjs  detail.mjs  d2.mjs  d3.mjs  d4.mjs  d5.mjs  d6.mjs  d7.mjs  d8.mjs
ledger.mjs  home.mjs  knowledge.mjs  announcement.mjs  admin.mjs  masterdata.mjs
lazy-load.mjs（按需加载实测）  fake-clamd.mjs（模拟 clamd 守护进程）
make-fixtures.mjs（一次性生成 Office 预览样本）  open-app.mjs
package.json  package-lock.json  fixtures\preview-sample.pptx
（node_modules\ 不入库）
```

### 2.7 文档与部署

```
docs\code-inventory.md                    一页式代码索引（接手先读）
docs\retrospective.md                     复盘 + 全量「问题→根因→处理」问题库
docs\delivery-status.md                   面向业务方的交付状态
docs\file-index.md                        本文件
docs\next-task-prompt.md                  下一轮开工提示词
docs\next-task-prompt-2.11-reports.md     2.11 报表提示词（KPI 口径未定，存档）
docs\templates\XTE-0071.docx              8D 报告模板
docs\reference\shell.js  docs\reference\mock-data.js   从原型拷来的参考实现

deploy\docs\QMS-生产部署方案.md            生产部署方案（阶段 A 已完成；B–D 待做）
deploy\docs\QMS-生产部署方案.html          同一份的可双击版本
deploy\templates\application-prod.yml.template  生产配置模板（@@TOKEN@@ 占位）
（deploy\scripts\ 安装/升级/回滚脚本尚未创建，属阶段 B）
```

---

## 三、其它工作区

```
qms_prototype\                     需求原型（纯 HTML）
  index.html  complaint-new.html  complaint.html  complaints.html  kb.html
  reports.html  report-8d.html  report-send.html  admin.html  why-editor.html
  assets\js\  assets\css\
  _tools\_out\requirements.txt     需求正文（可搜「3.12」「3.16」）
  _tools\_out\media\               需求内嵌图片
  _tools\_out\xte0071.txt  c2501869.txt   报告模板与样例的抽取文本

qms_backlog_update\                需求 / Backlog 工作簿与转换工具
  _verify\backlog_all.txt          全量 Backlog（可搜 PS-xxx）
  _verify\backlog_deps.txt  _verify\backlog_verify.txt  _verify\datadict_all.txt
  backup\*.xlsx                    工作簿历史备份
  _*.ps1  _*.json                  转换 / 应用 / 校验工具
```

---

## 四、不入库、但需要知道的目录

`qms-app\.gitignore` 覆盖以下内容——**备份或迁移机器时不要漏**：

| 目录 / 文件 | 内容 |
|---|---|
| `qms-app\tools\` | 绿色版 JDK 21 / Maven / Git；`tools\_out\` 里是构建日志、验收报告与全部截图 |
| `qms-app\config\.env` | 数据库口令 + JWT 密钥（**唯一持有密钥的地方**；`.env.*` 变体一律不入库） |
| `qms-app\data\attachments\` | 上传的附件文件（元数据在数据库里） |
| `qms-app\logs\` `qms-app\run\` | 运行日志与 pid 文件 |
| `qms-app\frontend\node_modules\` `qms-app\e2e\node_modules\` | 前端与 e2e 依赖 |
| `qms-app\backend\target\` | 构建产物 `qms-api.jar` |
| `qms-app\frontend\dist\` | 前端构建产物（会打进 jar） |

---

## 五、快速进入

```powershell
# 准备环境（一次）
& "C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\scripts\setup-local-toolchain.ps1"

# 构建 + 启动（单端口 8080）
& "...\scripts\frontend-build.ps1"
& "...\scripts\backend-build.ps1"
& "...\scripts\qms-server.ps1" -Action Start      # Start | Stop | Status | Restart

# 跑验收
& "...\scripts\verify-auth.ps1"
& "...\scripts\ui-admin.ps1"
```

> 全部脚本都写明了各自的用途、参数与用法（文件头部注释），且路径集中在 `scripts\_paths.json`。
