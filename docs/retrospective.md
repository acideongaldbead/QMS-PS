# QMS 生产化项目 · 复盘与踩坑集

> 本文件回答两个问题：**这一轮做得怎么样**（复盘），以及**以前踩过的坑都是什么、怎么解决的**（问题库）。
> 面向「接手新任务的人或下一个会话」。开工前先扫 `docs/code-inventory.md`，再扫本文件第 3 节。
>
> 最近更新：2026-10-15（本轮：**公告管理 + 公告正文富文本**；上一轮：阶段 2.12 知识中心）。

---

## 1. 上轮复盘：阶段 2.9 台账 + 2.10 首页 + 遗留清理

### 1.1 交付了什么

| 项 | 内容 | 验收 |
|---|---|---|
| 2.9 问题解决台账 | 双页签（与我相关 / 全部数据）+ 简易/高级筛选 + 排序白名单 + 分页 + 列设置 + 批量选择 + xlsx 导出 + 复制投诉 + 演示数据 seed | `verify-ledger` 54 项 / `ui-ledger` 20 项 |
| 2.10 首页工作台 | 4 指标卡 + 待办按阶段表真实聚合 + 超期预警条 + 系统公告 + 详情页 `?tab=` 一键定位 | `verify-home` 43 项 / `ui-home` 26 项 |
| 遗留清理 | ① 公告 NEW 按人未读（V18）② 详情页「沟通与流程日志」页签 ③ **报告审批接线并卡住发送** ④ 8D 报告 **PDF 导出** | `verify-report` 41→60 / `verify-complaint` 43→53 / `ui-d8` 7→18 |
| 规模 | 后端新增 18 个文件、前端新增 2 并改写 10、脚本新增 8 / 修改 7、迁移 V17–V18、文档 3 份 | API 验收累计 **577 项**，UI 端到端累计 **≈144 项**，全绿 |

### 1.2 做对了什么（值得下一轮继续）

1. **先把口径问清楚，再动手**。三处会改动既有行为的分叉（审批是否卡住发送 / PDF 是服务端还是浏览器打印 / NEW 是按人未读还是时间窗）用一次提问定下，避免了做完再返工。**越是有多种合理做法的地方，越要在写代码前确认。**
2. **一处判定收进数据库函数**。「与我相关」横跨主表 5 列 + 7 张子表的 owner，收进 `complaint_related()`（V17）后，台账列表、两个页签计数、首页指标卡都调它——**首页与台账的数字不会漂移**，验收脚本还会交叉核对两处必须相等。
3. **「未完成」读字典而不是硬编码**。首页待办判断某阶段任务是否结束，用的是 `status_code.is_final`，不是写死一排状态码——以后加状态只改字典。唯一例外（D6「已实施待验证」）有注释说明为什么。
4. **演示数据走真实 API 造**。`current_stage` 与 `status_code` 的对应关系（7 个状态 ≠ 9 个阶段、D2 还有两条分支）只有应用自己推进才自洽；手写 INSERT 迟早造出界面渲染不出的状态。
5. **改动被验收覆盖的行为时，一次改齐所有走那条路径的脚本**。加审批闸门时同步改了 `verify-report` / `ui-d8`+`d8.mjs` / `seed-demo-showcase` / `seed-demo-ledger` 五处，回归一次跑通（见 3.7-5）。
6. **每个功能都先有断言再交付**。本轮没有一处「功能做完但验不了」；`_check-ps1-encoding.ps1` 这个守卫星也两次替我拦下了错误。

### 1.3 做得不够（含我自己造成的返工）

| 现象 | 根因 | 处理 / 教训 |
|---|---|---|
| 编码守卫**两次**抓到我往 `.ps1` 里写中文注释（一次是 `verify-complaint.ps1` 的分节标题、一次是 `seed-demo-ledger.ps1` 的说明注释），而且两次都是「关于中文/MY 相关」的注释 | 规则是硬的，但写注释时不自觉 | 规则改成肌肉记忆：**`.ps1` 里一个中文字符都不能有**，注释也写英文 |
| 公告 NEW 的第一版断言**静默假通过** | PowerShell 5.1 的 `Invoke-RestMethod` 把 JSON 数组当单个对象写管道，`@(Invoke-RestMethod ...)` 恒为 1 个元素，`.Count` 永远等于 1 | 先赋值再 `@()`（见 3.2-14）。**教训：断言必须能失败**——凡是「恒真」的断言都是负债 |
| 演示 seed 被应用自身校验挡住**两次**（目标日期早于开始日期、任务完成日早于计划开始日） | 造数据时只想着「数据看起来合理」 | 造数据前先过一遍该业务对象的校验规则（见 3.3-4） |
| PDF 断言先写了「>20KB 才算合格」，结果**合格文件只有 14KB** | 阈值拍脑袋，没先看真实产物 | 先跑一次拿到真实量级再定阈值（见 3.7-4） |
| V17 已经应用到库上之后又改了函数内容，导致 Flyway checksum 需要手工修历史 | 迁移是「只追加」的，我改的是已应用的迁移 | 想清楚再落盘；真改了就把 `flyway_schema_history` 里那一行删掉让它重新应用（见 3.3-5） |
| 台账页第一版把「产品类型」列取成了产品主数据描述，且 `页面文案` 与原型的栏目含义不符 | 照着原型列名动手，没核对它指向的主数据 | 列名与取值来源要成对确认（见 3.5-4） |
| 首页待办条目/公告条目文字居中（应为左对齐） | `.file-item` 是原型给 `<a>` 写的样式，换成 `<button>` 后继承了按钮的居中 | 复用原型样式类时注意宿主元素（见 3.5-5） |

### 1.4 关键决策与「放弃了什么」

| 决策 | 为什么这么定 | 放弃了什么 |
|---|---|---|
| 「与我相关」用**最宽口径**（4 责任人 + 发起人 + 各阶段任务 owner） | 用户拍板；被派了某阶段任务的也算「我的单」 | 需要 7 个子查询，比单表过滤重；靠 `complaint_related()` 收口来抵掉复杂度 |
| 待办用**真实任务聚合**而不是按阶段派生 | 完成任务后条目真的消失，符合需求 3.0 的「失效分析记录、待审批报告、待处理措施」 | 8 条查询 + Java 侧合并，比「一条 SQL 按阶段派生」贵得多 |
| 报告审批**卡住发送** | 报告发给客户并结案是不可逆动作，值得第二双眼睛；否则「审批」只是装饰 | 必须同步改 4 个既有脚本/种子，且发送流程多两步 |
| PDF **服务端生成**（PDFBox + 内嵌中文字体） | 与 D8 现有 POI 生成 docx 一脉相承，产物可被断言（`%PDF` 魔数） | 新增依赖 + 字体路径配置；排版比 Word 简化（段落式，非版式还原） |
| 公告 NEW 用**按人未读**（服务端表） | 换设备/换浏览器不该让已读的公告重新变回未读 | 多一张表 V18 + 一次写接口 |
| 台账**删掉**「流程类型」列与筛选 | `complaint.process_type` 恒为 `'8D'`，原型那四类中文流程类型在真实系统没有数据支撑 | 与原型少一列一筛（已在文档里标注为刻意偏离） |
| 导出 Excel 提前到本轮（需求上属 3.10） | 用户要求，且它是台账唯一的批量出口 | 3.10 做报表时不要再重复实现一遍 |

---

## 2. 历史阶段要点（供定位）

- **阶段 1（2026-10-12）**：登录/JWT/锁定、RBAC（25 权限 × 4 角色 / 58 映射）、主数据只读接口、前端外壳（导航门控 / 密度 / 中英切换）。`verify-auth` 21 + `verify-masterdata` 25。
- **阶段 2 · 2.1–2.8（2026-10-13）**：**8D 主线 D0–D8 全闭环**——登记 D0–D1、附件（白名单 + Tika 内容嗅探 + 50MB + 可插拔杀毒）、样品与物流、D2 验证与有效性判定、D3 遏制、D4 根因（3x5Why 思维导图 + 鱼骨图，均按版本追加）、D5/D6/D7 措施与预防文件、D8 报告/Word 导出/发送/结案。
- **阶段 2 · 2.9–2.10 + 遗留清理（2026-10-14）**：见第 1 节。
- **阶段 2 · 2.12 知识中心（2026-10-14）**：见第 6 节。
- **未开始**：2.11 报表与分析（需求 3.10）—— 后端与前端都还是零，`ReportsView.vue` 是占位页。
  需求范围内同样未做的还有 **3.12 权限管理界面**（`/admin` 占位，只有后端 RBAC 强制 + 只读接口）、
  **3.13 通知与提醒**（TPT 提醒 / 飞书）、**3.14 系统集成**（主数据为本机种子，未接 SAP/PLM/MDM/MES）。

---

## 3. 问题 → 根因 → 处理（全量，按主题分组）

### 3.1 环境与工具链

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 下载 JDK/Maven/Git 卡在 0 字节 | GitHub release 在本网络下被墙；Adoptium API 只返 307 | 一律走清华 TUNA 镜像；Maven 走阿里云镜像（`config/maven-settings.xml`） |
| 2 | 解压便携版 Git 后只剩 `bin` 里三个 exe | PortableGit 的 SFX 直接铺开、没有外层目录 | 不要按「取第一个子目录」解压 |
| 3 | 脚本里 `java -version` 让整个脚本中断 | `2>&1` + `$ErrorActionPreference='Stop'` 会把原生命令的 stderr 包成 ErrorRecord | 用 `*>` 落文件再读；脚本顶层用 `Continue`（另见 3.2-3） |
| 4 | 本机 PostgreSQL 连不上 5432 | 实际监听 **5433** | `_paths.json` / `.env` / 各脚本统一 5433；口令在 `config/.env` |

### 3.2 PowerShell / 脚本

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 中文期望片段永远匹配不上（功能其实是对的） | PS 5.1 把**无 BOM** 的 `.ps1` 按 GBK 解码 | `.ps1` 保持纯 ASCII，中文只放 `_verify_expectations.json`（UTF-8）；`_check-ps1-encoding.ps1` 守门 |
| 2 | 单元素管道结果被当成字符串，`$vers[$vers.Count-1]` 取到首字符 | 管道会拆包 | 索引前 `@()` 包住（同 3.2-9） |
| 3 | 函数里 `Write-Output` 写日志，把「下载失败」也当成成功返回 | 输出污染了函数返回值 | 日志走 `[Console]::Out.WriteLine` |
| 4 | `$args` 当变量名报错 | `$args` 是 PowerShell 自动变量 | 换名 |
| 5 | 第一次提交成功、后续都 500 | 函数返回**单元素数组**被拆包成裸对象，服务端按对象解析数组失败 | `return ,$arr`（前置逗号）；本轮 `ui-ledger` 又踩了一次，同样修法 |
| 6 | 验收脚本里「期望 201」必失败、「期望 200」无条件通过 | `Invoke-RestMethod` 拿不到状态码 | 一律用 `Invoke-WebRequest` 取真实 `StatusCode` |
| 7 | 过滤后只剩一个对象时 `.Count` 取不到（假失败/假通过） | 单对象没有 `Count` | 写成 `@( ... | Where-Object {...} ).Count` |
| 8 | `ConvertTo-Json` 把单元素数组写成对象，服务端 400 | 管道输入会拆包 | `ConvertTo-Json -InputObject $payload -Depth 12` |
| 9 | `ConvertFrom-Json` 得到的对象不能新增属性，深拷贝失败 | PSCustomObject 结构固定 | 用递归 hashtable 深拷贝，不过 JSON |
| 10 | 从函数返回的数组在调用处变成标量，JSON 里 `[...]` 变 `{...}` | 同 5 | 同 5 |
| 11 | `psql -c` 传中文参数在 Windows 上失败（非法 UTF-8 字节） | 命令行按 GBK 传参 | SQL 保持纯 ASCII；需要中文就用 `psql -f` 跑 UTF-8 文件（迁移就是这么做的） |
| 12 | 打点日志出现「PASS … -> X-Ray not found」这种自相矛盾的行 | UI 脚本的 `note()` 无论成败都打印第三个参数 | 详情只在失败时打印 |
| 13 | 新增迁移后本地库不生效 | `db/migration` 在仓库根、不在 backend 模块里，Maven 没打进 jar 时 Flyway 静默什么都不做 | pom 里配 `<resource>` 打进 `classpath:db/migration` |
| 14 | 公告 NEW 的断言**静默假通过** | PS 5.1 的 `Invoke-RestMethod` 把 JSON 数组当**单个对象**写管道 → `@(Invoke-RestMethod ...)` 恒为 1 个元素，其属性才是数组 | **先赋值再包 `@()`**：`$r = Invoke-RestMethod ...; @($r | Where-Object {...}).Count`。反例：`(Api ...).body` 是属性取值，数组正常 |
| 15 | 写了中文注释的 `.ps1` 被自己的守卫拦下（两次） | 见 1.3 | 英文注释；提交前必跑守卫 |
| 16 | `$home = @(...)` 抛 `VariableNotWritable` 却**不终止**脚本，两条首页公告断言被歪曲 | `$home` 是 PowerShell 的**保留自动变量**（用户主目录）；`ErrorActionPreference='Continue'` 下赋值失败被忽略，`$home` 仍是主目录字符串，`@($home \| Where-Object {...})` 于是恒真/恒假 | 列表变量避开保留名（改用 `$homeList`）。同类：`$input` / `$args` / `$error` |

### 3.3 SQL / 迁移 / 数据

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 应用起来后所有表都「不存在」 | Hikari 连接没有 `search_path`，表都在 `qms` schema | `connection-init-sql: SET search_path TO qms, public` |
| 2 | 每个迁移文件单独 `SET search_path` 是必须的 | `psql -f` 每个文件是独立会话，V1 的设置不会继承 | 迁移开头统一写一行 |
| 3 | 校验工具报的迁移执行顺序与 Flyway 不一致 | `db-validate-migrations.ps1` 原来按文件名排序（V10 排到了 V2 前面） | 改为按**数字版本**排序（与 Flyway 一致） |
| 4 | 阶段/状态「看起来合理」的演示数据插不进去 | 应用自身的业务校验会挡住（`目标日期不能早于开始日期`、`任务目标完成日不能早于计划开始日`、D2 判无效即结案） | 造数据前先过一遍该对象的校验规则；演示数据**走真实 API**，让应用自己推进阶段与状态 |
| 5 | 改了已应用的迁移 → Flyway checksum 校验失败 | 迁移只追加；我动了已经 apply 过的 V17 | `DELETE FROM qms.flyway_schema_history WHERE version='17'` + `DROP FUNCTION`，重启即重新应用。**V1 基线才是逐字节冻结的那个** |
| 6 | SQL 函数在手工 psql 里报「关系 complaint 不存在」 | SQL 语言函数会被**内联**进调用方查询，用的是**调用方会话**的 search_path | 函数内表名写全 `qms.` 前缀（限定后仍可内联；改函数级 `SET search_path` 会阻止内联） |
| 7 | 从批次里移除样品后再也加不回来，被误报「记录已存在」 | 软删除 + **普通唯一约束**：被删的行仍占着唯一键 | 换成**部分唯一索引** `WHERE is_deleted = false`（基线别处本来就这么写） |
| 8 | 基线的 CHECK 约束与需求分支互相矛盾 | `ck_complaint_dates` 原为 `close_date >= start_date`，而「判无效直接结案」必然早于 start_date | 把约束改成它真正的语义（`close_date >= created_at::date`），见 V14 |
| 9 | 基线注释描述了一个不存在的字段 | `containment_action.completed_date` 的注释提到「完成早于计划日期时提示异常」，而该表**没有计划日期列** | **如实标注并请业务方定**，不擅自加列；2026-10-13 用户确认补录 → V16 加 `planned_completion_date` |
| 10 | **新增的权限码没有落到管理员头上** | V3 给管理员那批权限用的是当时的 `CROSS JOIN` 全量快照，之后新增的码不会自动获得 | 新增迁移里**显式** `INSERT INTO role_permission ... WHERE role_code='ROLE_ADMINISTRATOR' AND permission_code='新码'`，并在迁移里写明原因（V20 的 `knowledge:manage`） |
| 11 | **加权限码会打断断言权限总数的既有脚本** | `verify-masterdata.ps1` 有一条 `administrator sees 25 permissions` | 加码前先 grep 谁会断言这个数；本轮把 25 会同改成 26（`verify-auth` 那条用的是 `-ge`，不受影响） |
| 12 | 迁移校验脚本「跑起来就失败」 | `db-validate-migrations.ps1` 内 `dropdb --if-exists` 在无临时库时往 stderr 写中文提示，而脚本顶层 `$ErrorActionPreference='Stop'` → 第一条迁移之前就中止 | **不要用 `2>&1` 调用它**（`2>&1` 把原生 stderr 包成 ErrorRecord）；直接调用时 20 个迁移全部 OK |
| 13 | 想验证 V1 基线冻结，差点跑了个会**改文件**的脚本 | `sync-baseline-ddl.ps1` 是 `Copy-Item -Force` 的**覆盖式同步**，不是只读比对 | 自己算 SHA-256 对比（本轮：两文件 `BCF3E717…` 完全一致、无 BOM、152,758 字节） |

### 3.4 MyBatis / 后端分层

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 某个查询整体 500 | 用构造器映射 record 时，**每个构造参数都必须能对上某一列**（`FailureType.children` 这种树形附属字段没有列） | mapper 返回**扁平行 record**，树在 service 里拼；DTO 里不放没有对应列的字段 |
| 2 | 500 `Cannot convert the column of type VARCHAR to requested type OffsetDateTime` | MyBatis 的构造器映射是**按列位置**而不是按列名；我把 `publishedByName` 排在 `publishedAt` 前面、SELECT 顺序相反 | **SELECT 列序与 record 组件序逐一对齐**，两侧都加注释互相指认 |
| 3 | 想在库里把某字段**清空**，响应说清空了、库里还在 | MyBatis-Plus 的 `updateById` 默认跳过 null 字段 | 用 `LambdaUpdateWrapper` 显式 `.set(field, null)` 或专用 UPDATE 语句 |
| 4 | 请求体格式错误回了 500 | 缺异常处理 | `GlobalExceptionHandler` 补 `HttpMessageNotReadableException` / `MissingServletRequestParameterException` / `MethodArgumentTypeMismatchException` → 400 |
| 5 | 上传被拒绝时**最需要留痕**的审计行消失了 | 写在事务里、随后 `throw` 会被一起回滚 | `AuditLogService.recordRegardlessOfOutcome(...)` 用 `Propagation.REQUIRES_NEW` 独立提交。**规律：业务动作的审计随事务；被拒绝/失败的审计必须独立** |
| 6 | 启动即报 `Could not resolve placeholder` | `@Value` 解析不了 YAML 列表 | 列表类配置用 `@ConfigurationProperties` |
| 7 | `tika` 的 `detect(Path)` 不存在 | 2.9 版没有该重载 | 用 `detect(InputStream, String)`；它是**内容优先**的 → 改名的可执行文件仍被识别为 `application/x-msdownload` |
| 8 | 超过上限的上传被**静默拦掉**、不进校验层也没有审计 | 容器 multipart 上限与业务上限设成一样 | 容器 60MB / 业务 50MB，由校验层裁决并留痕 |
| 9 | 引入 `spring-boot-starter-security` 但没写配置，前端整个被 HTTP Basic 挡住 | Boot 默认配置 | 必须显式写 `SecurityConfig` |
| 10 | `Set.of(...).contains(null)` 直接 500（不像 HashSet 返回 false） | 不可变集合不允许 null 查询 | 拿可能为 null 的值查 `Set.of` 集合前先判空 |
| 11 | 业务异常自定义说明被吞掉，全变成「无权限执行该操作」 | 异常处理器把消息写死了 | 有自定义消息就用它，只有 Spring Security 自己的英文 "Access Denied" 才回落通用文案 |
| 12 | 一个功能「第二次操作没有审计」 | 审计写在了状态推进函数里，而该函数在「状态已是目标值」时直接 return | 凡有独立意义的动作（建任务、录结果）都**单独写一条审计**，不依赖副作用 |
| 13 | 分页查询的 count 可能算错 / 报错 | MyBatis-Plus 的 count 重写会删「未参与 WHERE 的 JOIN」、替换 select 列表；而台账 SELECT 里有函数调用、ORDER BY 里是表达式 | 全局关掉 join 优化 + Page 上 `setOptimizeCountSql(false)`，让它用子查询包住原查询 |
| 14 | 未登录/越权时前端拿到 500 或空白 | 认证/鉴权失败没走统一响应 | `SecurityConfig` 的 entryPoint(401) 与 accessDeniedHandler(403) 输出与 `GlobalExceptionHandler` 相同的 `{status,message}` 结构 |
| 15 | 报告审批的 403 说不出「该由谁批」 | 只回了通用文案 | 抛 `AccessDeniedException("只有该报告的审批人（张宏）可以给出结论")`，处理器会保留自定义消息 |
| 16 | **第一个 bigint 父主键的附件分支写不通** | 其余 9 类 biz_type 的父主键都是 varchar 业务号，`knowledge_article.article_id` 是 bigint：`article_id = #{bizId}` 报 `operator does not exist: bigint = character varying`；而 `CAST(#{bizId} AS bigint)` 会让非法 id **抛异常变 500** | 用 `article_id::text = #{bizId}`：任何输入都安全返回 0 → 404（表很小，不依赖索引），并在 `<when>` 上方写注释说明 |
| 17 | 加了 `org.jsoup:jsoup` 不写版本，**读 POM 阶段**就报 `'dependencies.dependency.version' ... is missing` | **Spring Boot 3.4.1 的父 POM 并不管理 jsoup 版本**（它管 tika/pdfbox 等，但 jsoup 不在其 BOM 内） | 配 `<jsoup.version>` 属性并在依赖里引用。**教训：别假设「Spring Boot 管所有常见依赖的版本」** |

### 3.5 前端 / Element Plus

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 表格里按文字找到按钮却点不动 | Element 的**固定列**（`fixed="right"`）会渲染两份，脚本点到了隐藏克隆 | 点击前过滤 `el.offsetParent !== null` |
| 2 | D3/D5 对话框里窄列的下拉框只显示「李…」、日期只显示「2…」（值其实存对了） | `el-form` 的 `label-width` **级联**进 `el-row` 里每个 `el-col` 的 form-item | 多列表单行用 `span=12 ×2` 或给窄列 item 单独收窄 `label-width`（D5 已修，D3 按用户要求保留原样） |
| 3 | 按需加载失效，一开页面就把编辑器全量下载 | 给**自带动态 import 的库**（mermaid）配了 `manualChunks`，把 60 个懒加载分包合并成 1 个 3.1MB 的包 | 什么都别配，交给 Rollup 自然分包（`vite.config.ts` 已写明原因） |
| 4 | 台账「产品类型」列显示成产品主数据的长描述，且有些行是「—」 | 我照原型列名取错了主数据（应取**产品类型字典**名，不是产品主数据描述） | 列名与取值来源成对确认；改用 `master_data_item(product_type)` 的名称 |
| 5 | 首页待办/公告条目文字**居中**（应为左对齐） | 复用了原型给 `<a>` 写的 `.file-item`，换成 `<button>` 后继承了按钮的居中 | 复用原型样式类时给宿主元素补 `text-align: left` |
| 6 | 改了接口字段名前端没报错但显示空白 | 前端类型是手写的（无 OpenAPI 生成） | 改后端 DTO 时同步改 `api/*.ts` 的类型与引用处 |
| 7 | **UI 脚本按 `data-*` 钩子找不到输入框**（`[data-kb-field-title] input` 报 No element found） | **Element Plus 的 `el-input`/`el-select` 会把 fallthrough 属性转发到内层控件**，属性实际落在 `<input>` 上，所以「后代」选择器匹配不到 | 钩子挂在**自己写的包装元素**上（`<div class="kb-field" data-kb-field-title>`），选择器才确定。另：`el-dialog` 里做上传后，**列表不会自己刷新**——文件是在对话框里加的，父组件看不见，给对话框加 `@closed="load"` 重读一次 |
| 8 | 窄窗口下文档行的标题与编号**在词中间折行** | `.file-item` 是 flex 行，标题与编号都是默认 `flex-shrink:1`，各自内部折行 | 标题 `min-width:0` + `text-overflow: ellipsis` 让它让位；编号与版本徽标 `flex: 0 0 auto` 保形。**这是 1280/1180 版式核对才看得出来的问题** |
| 9 | 共享 `.grid-sidebar` 在 ≤1280px 拍成单列，**筛选栏掉到列表下面**（要滚动才看得到分类） | 共享响应式规则为通用「主+侧」设计的 | 页内覆盖成「窄右栏」并延到 1100px 才收单列 —— 与 `HomeView` 同一种取舍（那里注释就写了「堆叠才是不可读的原因」） |
| 10 | 对话框里共享 `AttachmentPanel` 的「上传时间」列被挤掉 | 该面板各列 min-width 合计约 930px，而对话框正文只有约 750px | 知识中心的对话框开到 1000px（**不改共享组件**，避免动到 D2/D6/D8 的既有版面与截图） |
| 11 | 公告正文改 `v-html` 后首屏渲染出多余空行、块级样式不生效 | ① 旧的 `white-space: pre-wrap` 把每个标签边界都当换行；② **scoped 样式不作用于 `v-html` 子节点** | 去掉 `pre-wrap`；只读样式写 `.ann-body :deep(p/ul/ol/blockquote/h*)` |
| 12 | UI 脚本里「工具栏点一下 → 回车」被按钮吃掉，段落没断开 | 工具栏命令 `chain().focus()` 之后按钮仍短暂持有 DOM 焦点，紧接的 `Enter` 激活了按钮而非编辑器 | 连打键盘前显式 `page.focus('[data-rt-area] .ProseMirror')`；断言本身靠抽屉里的 `strong`/`li` 计数，不受此影响 |

### 3.6 浏览器 e2e（puppeteer-core → 本机 Edge）

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 用无头 Edge 跑多角色测试会串号 | access token 在 localStorage，共用 context 会互相覆盖 | **每个用户开独立 browser context** |
| 2 | 读 mermaid 图文本比对失败（`Moldtemperaturedrift`） | 多词标签被拆成多个 `tspan`，`textContent` 丢空格 | 比对前去空白 |
| 3 | `querySelector('svg')` 取到空图 | mermaid 会留一个隐藏的测量用 SVG | 按 `svg[id^="…"]` 或读容器文本 |
| 4 | `click()` 选不中思维导图节点 | mind-elixir 的选中监听在 **`mousedown`**（它支持拖拽） | 用 puppeteer 的真实鼠标点击 |
| 5 | 「先深链再测默认页签」量到的是上一次的 `?tab=` | `page.goto()` 只改 `#hash` **不会重挂组件** | 基准要在深链**之前**量；或强制 reload |
| 6 | 断言行数被固定列克隆骗了 | 同上 3.5-1 | 用**服务端给的文字**（如「共 N 条记录」）断言行数，别数 DOM 行 |
| 7 | 排序断言恒真（前后顺序一样） | 屏幕只有两行，且 Element 首次点击是**升序**、恰好与默认序相同 | 换默认序不同的列，或比对**整列顺序** |
| 8 | 「按需加载」以为是好的，实际不是 | 看构建产物判断不等于看浏览器真实请求 | 逐阶段记录浏览器请求与字节数（`e2e/lazy-load.mjs`） |

### 3.7 流程与交付

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| 1 | 功能做完但说不清对错 | 没有可复跑断言 | **每个阶段交付必须带**：API 断言 `verify-*.ps1` + 真机 UI 端到端 `ui-*.ps1`+`e2e/*.mjs`（截图落 `tools/_out/ui`）+ 既有脚本回归 |
| 2 | 改一处、坏一片（本轮加审批闸门时，四个脚本/种子都会走到发送） | 只改了实现没改调用方 | 改被验收覆盖的行为前，先 **grep 谁会走到那条路径**（`/send`、`/reports`），一次改齐再跑全量回归 |
| 3 | 界面「看起来对」但细节不对（如居中、列取错） | 只跑了断言，没看真机 | 新页面/新组件都要真机截图；整行铺开的版式在 **1280 / 1180** 两个宽度各截一张 |
| 4 | 断言写了「>20KB」，合格文件 14KB 被误判失败 | 阈值拍脑袋 | **先跑一次拿到真实量级再定阈值**；断言要能表达意图（「不只是个文件头」）而不是拍一个数 |
| 5 | 报告发送加了审批前置后，既有验收会全挂 | 见 2 | 同 2 |
| 6 | 评审意见可能与真实产出物相反 | 我凭常识假设「对客户的报告不该出现内部责任人姓名」，而真实样例恰恰**写明**了姓名与风险评估 | **不要凭常识假设客户文档的信息边界，要看真实产出物**；这条已回写进原型文档 |
| 7 | 业务方也不知道的字段（`4TG/5GT/6GT/MAG`、`mag`）被硬塞进界面 | 需求文档未给定义 | 界面上标注「待确认」并报给业务方，而不是自己编含义 |
| 8 | 一条**新加的**断言暴露出**既有**功能一直是坏的：`attachment.file_type` 是 `varchar(32)`，而 OOXML 的 MIME 类型长达 64–73 字符 —— docx/xlsx「宣称支持、实际必挂」，且报错是 `DataIntegrityTranslator` 的兜底文案「数据校验未通过」，与真实原因完全无关 | 基线的列宽只考虑了 `image/png`、`application/pdf` 这类短类型；而**旧验收只上传过 PNG**，docx/xlsx 从未被真正跑过 | V19 把列放宽到 `varchar(128)`。**教训：宣称支持 ≠ 被验证支持**——每种声明的格式都该有一条真调用它的断言 |
| 9 | 我以为「扩展名白名单 + 内容嗅探」两道理足矣，实测发现**宏文档拦不住**：Tika 按 OOXML 主部件名（`ppt/presentation.xml`）判类型，把「宏版改名成 .pptx」照样报成非宏类型 | `detect()` 得到的类型无法区分 docx/docm | 新增第三道检查：**OOXML 包内是否存在 `vbaProject.bin`**（宏的可靠信号），并用合成包在验收里证明 |
| 10 | `Map.of` 只支持 10 对键值，把白名单从 8 条加到 12 条会**启动即崩** | 用了 `Map.of` 而非 `Map.ofEntries` | 改 `Map.ofEntries`；扩这类静态表前先看上限 |
| 11 | **一条新写的断言暴露出真缺陷：附件写权限形同虚设** | `AttachmentController.MAY_ATTACH` 是**扁平**的 `hasAnyAuthority`，把所有 `*:edit` 并列 → **持有任一编辑权限就能往任意类型挂附件**。实测「只有 `rootcause:edit` 的质量工程师」能把文件传进知识文档，直接架空「知识中心只由 `knowledge:manage` 维护」 | `AttachmentBizType.WRITE_PERMISSIONS`（biz_type → 该类型自己的编辑权限）+ `AttachmentService.requireWritePermission`；摆位有讲究：在 `requireSupportedBiz` **之后**（未知类型仍回 400）、父存在性检查**之前**（未授权者不能拿它探测 id）。回归 `verify-attachment` 40 项与 `verify-actions`/`verify-report` 全绿，确认既有合法路径没被误伤 |
| 12 | **以为「未完成的页面」其实是死路由** | `WhyEditorView.vue`（`/complaints/:id/root-cause/:rcId/why`）一直是占位页，但**全仓库只有 router 定义引用它**，同样的功能早已在 D4 页签里实现 | 已删（view + 路由 + 两个语言包的 `page.whyEditor` 键）。**盘点「未完成」时先 grep 有没有入口**，别把残留当需求 |

---

## 4. 已定口径（2026-10-14 用户拍板，本轮已落地）

| 问题 | 决定 | 落地 |
|---|---|---|
| 知识中心的文件怎么承载 | **系统内上传**（走通用附件表） | 附件扩展名白名单加 `doc/docx/xls/xlsx/ppt/pptx`（原已有 pdf/mp4 等），同步扩 `FileValidator` 的第二道内容类型白名单 |
| 是否需要「客户版 / 内部版」双版本 | **不要** | 删掉发送页那行恒真的「客户版」校验（原本等于没校验）；报告只有一份，内部批注本来就不进报告 |
| D7/D8 以谁为准 | **以 XTE-0071 模板为准**（模板有 D7/D8，样例缺 D7） | Word/PDF/页面三处的尾部改为：D7 系统性措施 → **Read-across** → **D8 TEAM RECOGNITION** →（保留）SIGN-OFF AND DISTRIBUTION；模板原文收进 `docs/templates/XTE-0071.docx` |
| 单号位数 | **C + 4 位年 + 5 位序号**（保持需求口径） | 无需改动；系统单号即报告抬头的 Nexperia Reference Number |
| 报告抬头字段 | **保持现状**（沿用样例的 15 项，不用模板的 5 项） | 已实现；**`Diffusion Process` 无对应字段**属已知且已接受 |
| D1 角色名 | **保持现状**（用业务角色名，不改成模板的 Team Leader / Team Member） | 已实现，不需改动 |
| Read-across 与 Team Recognition 是否要由系统填写 | **暂时不需要** | 按模板原文打印提示并留空，是**最终形态**（三处代码注释已注明是业务决定，不是待补） |
| 老格式（doc/xls/ppt）无断言覆盖 | **接受**（放行靠白名单，内容门与 Office 新格式共用同一段代码） | 作为残余风险记录在案 |
| **知识中心的文件怎么承载** | **系统内上传**（走通用附件表），不接外部共享盘 | 需要一个附件 biz_type + 三道文件校验的既有能力（已就绪） |
| **知识中心做不做「经验分享」** | **不做**——需求 1.5 明确把经验分享模块排除在一期之外 | `knowledge_tag` / `knowledge_article_tag` / `subscription` / `source_complaint_id`（结案后沉淀经验）本轮**一行代码都没碰** |
| **知识中心的维护权限** | **新增 `knowledge:manage`**（只给管理员），不复用 `admin.all` | 一条迁移 + 角色映射；换来的是可以单独授权、且能作为「附件写权限」按类型判定的依据 |
| **文档分类怎么落** | **原型 4 类 + 数据字典**（`master_data_item` 的 `knowledge_category`） | 以后加分类是改数据不是改代码；代价是新引入一个 md_type |
| **要不要给 `knowledge_article` 加列** | **加** `doc_code` / `title_en` / `version` / `summary` | 基线的表撑不起原型要展示的编号、中英双标题（3.17）、版本与描述；代价是一条 ALTER |
| **版本历史怎么承载** | **不建版本表**：`version` 是管理员手填字符串，历次上传的文件全留在附件面板里 | 一条「版本历史」，换来零新表；代价是没有「哪一版生效」的结构化表达 |

**顺带查实的两个事实**（原判断有误，此处更正）：
- **模板抬头只有 5 项**（Organisation / Process / 8D case nr / Opened / Closed）；那 15 个字段（Customer / Fail Qty / 12NC / Package …）是**样例** C2501869 的抬头，不是模板的。
- `C2501869.docx` 与 `C2601009.docx` **SHA-256 完全一致**（同一份文档两个文件名）——「文件名与正文单号对不上」由此收窄为「以正文的 C2601009 为准，还是以文件名的 C2501869 为准」。

## 5. 仍然悬着 / 交给下一轮的提醒

1. **2.11 报表与分析**仍未动（后端与前端都是零）；相关表 `report_config` **基线里已经存在**。动手前读 `docs/next-task-prompt.md`（已改写成 2.11 的提示词，含必须先问的口径）。**2.12 知识中心已于 2026-10-14 完成**（见第 6 节）。
5. **需求范围内还没做的其它章节**：**3.12 权限管理界面**（`/admin` 占位——后端 RBAC 强制与只读接口都在，缺的是角色/权限的配置界面）、**3.13 通知与提醒**（TPT 自动提醒与飞书集成，表与 `notification_rule` 3 条已种、无 Java 实现）、**3.14 系统集成**（主数据为本机种子，未接 SAP/PLM/MDM/MES；FMEA 属二期）。
2. **演示数据不可能覆盖真实复杂度**：`mag/4TG/5GT/6GT` 与 `Diffusion Process` 的含义未定、TPT 口径未定、部门级数据隔离未做（一期明确不做）。
3. **需求里尚未实现的两条**（属后续范围）：报告 owner 的**自动通知/审批提醒**与 **TPT 自动提醒**（表与配置都在、`notification_rule` 种了 3 条，无 Java 实现）；3.10 的**批量导出关联 8D 报告压缩包**（目前只有 Excel 清单）。
4. 新增的依赖与配置：`mybatis-plus-jsqlparser`（分页拦截器）、`pdfbox 3.0.3`（PDF）、`qms.report.pdf-font`（PDF 中文字体路径，缺字体时明确报错）。

---

## 6. 本轮复盘：阶段 2.12 知识中心（2026-10-14）

### 6.1 交付了什么

| 项 | 内容 | 验收 |
|---|---|---|
| **知识中心（需求 3.11）** | V20（`knowledge_article` 扩 4 列 + `knowledge_category` 字典 + `knowledge:manage`）；后端 `knowledge` 模块（列表带最新附件、分类计数、增删改查）；前端整页（分类分组列表 + 分类筛选与计数 + 关键词检索 + 下载 / PDF·图片预览 + 管理员新建编辑软删与附件上传）；附件第三个 biz_type 接线 | `verify-knowledge` **68 项** / `ui-knowledge` **34 项** |
| **顺带清理** | 删除死路由 `WhyEditorView`（view + 路由 + 两个语言包的键）；附件写权限按 biz_type 收紧（见 3.7-11） | `frontend-build`（含 vue-tsc）通过；`verify-attachment` 40 项回归 |
| 规模 | 后端新增 5 文件 / 改 4；前端新增 1 / 改 7 / 删 1；迁移 **V20**；脚本新增 3（`verify-knowledge.ps1`、`ui-knowledge.ps1`、`e2e/knowledge.mjs`）/ 改 2；文档 4 份 + 记忆 2 份 | 全量回归 **API 673 项 / UI 186 项全绿** |

### 6.2 做对了什么（值得下一轮继续）

1. **先把口径问清再动手**。边界（要不要做经验分享）/ 权限（`admin.all` 还是新码）/ 字段（要不要加列）三处都会影响表结构与界面，一次问定，整轮没有返工。
2. **列表 SQL 用 `LEFT JOIN LATERAL` 取「最新附件」**：每行需要显示文件名/大小/类型并直接下载，一次查询拿全，前端不做 N+1。
3. **写「工程师不能挂附件」这条断言，抓出了既有的越权口子**（3.7-11）。这条断言本来只是要实现「只由管理员维护」，结果暴露了 `MAY_ATTACH` 的扁平白名单。**能失败的断言才是有效断言**——本轮又一次证明。
4. **真机截图核对两个宽度**，发现了三个断言根本看不出来的问题：标题在词中间折行、筛选栏被拍成单列、对话框里附件表被挤掉一列。**布局问题只有看图才知道。**
5. **独立复核很有价值**：把 20 个迁移在临时库从零重放（证明迁移链自洽，不是只证明「增量能跑」）、比 SHA-256 证明 V1 真的冻结。

### 6.3 做得不够（含我自己造成的返工）

| 现象 | 根因 | 处理 / 教训 |
|---|---|---|
| 断言里写死了文件名 `manual.png`，而浏览器上传的是**磁盘上的文件名** `kb-upload.png` | 没想到「UI 上传的文件名 = 传给 `uploadFile` 的路径的文件名」 | 期望值要从**实际输入**推导（`path.basename(png)`），别抄另一个场景的名字。排查时还差点被自己 `slice(0,160)` 的截断骗过去 |
| 第一次把 `data-*` 钩子挂在 `el-input` 上，选择器 `[data-x] input` 找不到 | 不知道 Element Plus 会把 fallthrough 属性转发到内层 `<input>` | 见 3.5-7；**钩子挂在自有包装元素上** |
| 在编辑对话框里上传文件后，**列表行不刷新** | 文件是在对话框内部加的，父组件的 `rows` 看不见 | 对话框 `@closed` 时重读列表（见 3.5-7） |
| 差点把「`2>&1` 引起的脚本中止」报成「迁移校验失败」 | 没先怀疑调用方式 | 复核工具时先分清**是脚本的问题还是调用方式的问题**——本项目第 1 条坑就是这个 |

### 6.4 关键决策与「放弃了什么」

| 决策 | 为什么这么定 | 放弃了什么 |
|---|---|---|
| **版本历史 = 附件列表**（不建版本表） | `version` 是管理员手填字符串，历次上传的文件本来就全留在附件面板里 | 没有「哪一版生效」的结构化表达 |
| **创建即发布**（`ARTICLE_PUBLISHED`） | 草稿/归档本轮不在界面暴露 | 发布审批流 |
| **页内覆盖 `.grid-sidebar`**（窄右栏，1100px 才收单列） | 共享规则在 ≤1280px 拍成单列，**筛选栏会掉到列表下面**，要滚动才看得到分类 | 知识中心页的响应式断点与其它页面不一致（已写注释说明理由） |
| **对话框开到 1000px，不动共享附件面板** | 该面板各列 min-width 合计约 930px | 对话框比一般弹窗宽；没有去改 D2/D6/D8 共用的组件 |
| **分类用字典而非自由文本** | 以后加分类是改数据 | 新引入一个 md_type，且下拉多一次字典加载 |

---

## 7. 本轮复盘：公告管理 + 公告正文富文本（2026-10-15）

### 7.1 交付了什么

| 项 | 内容 | 验收 |
|---|---|---|
| **公告管理（PS-003）** | 新增 `announcement:manage` 后台页：列表（状态筛选 全部/草稿/已发布/已下架）+ 新增/编辑（**标题 / 发布时间 / 富文本正文**）+ 发布 / 下架 / 重新发布 / 软删。**不新增权限码**（`announcement:manage` 在 V3 已种、管理员已持有） | `verify-announcement` **64 项** / `ui-announcement` **17 项** |
| **公告正文富文本** | 正文改存**净化后的 HTML**：后端新增 `common.richtext.HtmlSanitizer`（jsoup 白名单，**写入侧**净化）；前端新增 `components/RichTextEditor.vue`（TipTap，**懒加载**）；首页抽屉改 `v-html` + `:deep()` 只读样式 | 净化/往返字节断言 + `e2e/lazy-load.mjs` 登录首屏不含编辑器 |
| **数据迁移** | **V21**（纯数据、无 schema 变更）：把 V9 的 3 条纯文本公告包成 `<p>`，幂等 | `db-validate-migrations` V1–V21 全绿 |
| 规模 | 后端新增 3 / 改 3；前端新增 3 / 改 5；迁移 V21；脚本新增 2 / 改 2；e2e 新增 1 / 改 1 | 回归：`verify-home` 44 / `verify-masterdata` 25 / `ui-home` / `ui-lazyload` / `verify-knowledge` 68 / `ui-knowledge` 全绿 |

### 7.2 做对了什么（值得下一轮继续）

1. **先问口径再动手**。两处会改变行为的分叉（状态流转是否含草稿/下架、发布时间是否可手改）一次问定，整轮没有返工。
2. **净化摆在写入侧**，读取原样返回——于是「存盘字节往返一致」这条断言才成立，也避免了每次读都重排 HTML。
3. **懒加载守住了**：编辑器用 `@tiptap/core` 的命令式 `Editor` 在 `onMounted` 里 `await import()`，登录首屏字节数不变（3138 KB），`e2e/lazy-load.mjs` 新增一条断言把意图固化。
4. **断言必须能失败**：写「正文是 HTML」「空白正文被拒」两条新断言时，前者抓出了 `$home` 被保留名污染导致的假通过，后者抓出我**漏实现**的服务端「空段落」校验——两条都当场修掉。

### 7.3 做得不够（含我自己造成的返工）

| 现象 | 根因 | 处理 / 教训 |
|---|---|---|
| 计划里写了服务端「空段落也算空正文」的校验，**实现时漏了**，被自己的断言抓出来 | 计划与实现之间的落差 | 见 3.4-17 附近；**先写断言再写实现**能让这种漏项立刻显形 |
| 两条首页公告断言一度**假通过**（`$home` 是保留变量） | 见 3.2-16 | 变量命名避开 PowerShell 保留名 |
| UI 脚本第一版「工具栏点击 → 回车」没断段，截图里加粗行与列表项粘在一起 | 见 3.5-12 | 断言虽通过，但**看截图**才发现排版不对——布局/结构问题只有看图才知道 |
| 加 jsoup 忘了版本号，构建在**读 POM 阶段**就挂 | 见 3.4-17 | 第一次构建即暴露，代价很小 |

### 7.4 关键决策与「放弃了什么」

| 决策 | 为什么这么定 | 放弃了什么 |
|---|---|---|
| 公告正文**只做文字格式**（无图片/附件） | 与知识中心「文件走附件」的既有口径一致；内联图片需处理鉴权图片的 blob 转换，复杂度不划算 | 原型工具栏里的「插入图片」暂不实现（二期） |
| **完整状态流转**（草稿/已发布/已下架） | 基线 `publish_status` 本就预留三值；「下架」对过期公告是真实需要 | 比「新增即发布」多两个动作与两条 409 分支 |
| 发布时间**管理员可指定/修改** | 用户需要补录历史公告 / 控制首页排序 | 需处理 `LocalDateTime`→`timestamptz` 的时区转换（单机固定时区，风险可控） |
| **编辑不设「发布后须先下架」门槛** | 用户要求「可编辑 + 可改时间」；轨迹由审计 before/after 兜住 | 已发布正文可被原地改动（审计可追溯） |
| 净化器选 **jsoup** 而非 OWASP sanitizer | jsoup 零运行时依赖、`Safelist` 一行白名单；Tika 只带了 core 不带 jsoup，版本自钉 | 需自己维护白名单（已与编辑器能力对齐，有断言守住） |
| 管理表格**不设 `fixed="right"`** | 避免 Element 固定列渲染两份带来的脚本点击歧义；收窄列宽后 1180px 不横向滚动 | 更窄窗口下操作列可能需横向滚动 |
