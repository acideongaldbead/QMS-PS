# 下一步任务提示词（2.11 报表与分析）

本文件是**开新会话时直接复制粘贴的提示词**，写于 2026-10-14，项目状态见 `docs/code-inventory.md`
与记忆文件 `~/.claude/projects/C--Users-Vivien-ma/memory/reference_qms_app_workspace.md`。

> 2.12 知识中心已于同日完成（见 `docs/code-inventory.md` §9）。**只剩 2.11 报表与分析。**
> 若想先插队做需求 3.12 系统管理界面或 3.13 通知提醒，把下面「本次范围」换掉、并把
> 「要确认的问题」换成对应的口径问题即可，其余照抄。

---

```
继续 QMS 生产化项目（问题解决管理系统），本次做 2.11 报表与分析。
工作区：C:\Users\Vivien.ma\Documents\Vivien\ps\qms-app\
（后端 Spring Boot 3.4.1 / Java 21 / MyBatis-Plus / Flyway；前端 Vite+Vue3+TS+ElementPlus+Pinia；单端口 8080，前端 dist 打进 jar）

【第一步：先把上下文读进来，不要凭猜测动手】
1. docs\code-inventory.md —— 一页式代码索引（目录、后端模块、前端 views/api、迁移 V1–V20、
   脚本/e2e 清单、各阶段完成度、2.9–2.12 现状与缺口、复用要点与踩坑 20 条）。
2. 记忆文件 ~/.claude/projects/C--Users-Vivien-ma/memory/reference_qms_app_workspace.md
   —— 阶段总览 + 构建链路 + 断言清单 + 迁移编号 + 已踩的 54 条坑（务必先读，50–54 是本轮新增）。
3. docs\retrospective.md 第 3 节 —— 全量「现象→根因→处理」问题库（写代码前扫一遍）。
4. 需求与原型：需求正文 ...\ps\qms_prototype\_tools\_out\requirements.txt（搜「3.10」「报表」）；
   原型 ...\ps\qms_prototype\reports.html + assets\js\（统计报表 + KPI + TPT + 自定义报表）。

【已完成进度，供你定位】阶段 1 骨架、8D 主线 D0–D8（2.1–2.8）、2.9 台账、2.10 首页、
遗留清理（公告 NEW / 沟通与流程日志 / 报告审批卡住发送 / 报告 PDF 导出）、
业务口径收口（附件 Office 全格式 + 宏拒收 / 取消双版本 / 报告对齐 XTE-0071）、
**2.12 知识中心（后端 + 前端 + 附件接线 + 死路由清理）** 全部完成。
API 验收 **673 项** + UI 端到端 **约 186 项** 全绿。**只剩 2.11 报表与分析没做，
后端与前端都还是零（`ReportsView.vue` 是占位页）。**

【本次范围】2.11 报表与分析（需求 3.10）。

【动手前必须先问清的问题（原型与需求里就标着「待业务方确认」）】
- **三个 KPI 的口径**：需求 3.10 只给了名字（BG Q「Complaints (valid, #)」、Sales Quality
  「Complaint TPT」、BG Q「Customer incident」），**没有给公式**。原型里也标着待确认。
  必须问清：分子分母、时间口径（按登记日？结案日？）、是否含「投诉不成立」的单。
- **自定义报表**：基线表 `report_config`（`report_name`/`report_type`/`fields_json`/`filters_json`
  jsonb/`is_shared`，注释写「可导出 PPT/PDF」）**已在 V1**。本轮做不做自定义报表配置界面？
- **导出格式**：需求 3.10 写「可导出 PPT, PDF」；现有能力是 POI（Word/Excel）+ PDFBox（PDF）。
  PPT 需要新增依赖（POI 的 XSLF 在 `poi-ooxml` 里，已随 poi 引入，需确认）。
- **需求 3.10 还提到「批量导出 Excel 投诉清单 + 其关联 8D 报告（压缩包）」** —— 目前只有
  Excel 清单（2.9 的台账导出）。这个压缩包是本轮做还是继续留？
- 8D 报告状态统计报表的维度（按阶段？按状态？按客户/产品？）与「集成 BI 平台」的关系
  （BI 是一期外的集成项，本轮大概率只做系统内报表）。

【工作方式（本项目硬要求，请严格遵守）】
1. 先进入计划模式，用探索代理摸清可复用资产（`knowledge`/`report` 模块的分层样板、
   `LedgerView` 的筛选+导出骨架、`e2e/home.mjs` 的双宽度版式核对、`verify-knowledge.ps1`
   的「列表+字典+附件」三件套骨架），把方案写进计划文件给我确认后再动手。
   **阶段边界等我的指令**，不要自己一路做下去。
2. 后端镜像 `knowledge`/`report` 的分层：Controller（@PreAuthorize，类上 @RequestMapping("/api")）
   + Service（@Transactional + 审计）+ Mapper（注解 SQL、`<script>` 动态片段、record 投影）
   + dto/XxxDtos（record）。**新增 mapper 的 record 必须让 SELECT 列序与组件序一一对齐**
   （MyBatis 按列位置映射）。
3. 每阶段交付必须带：可复跑的 API 断言 verify-xxx.ps1（**纯 ASCII**，中文期望片段放
   scripts\_verify_expectations.json）+ 真机 UI 端到端 ui-xxx.ps1 + e2e\xxx.mjs（截图落
   tools\_out\ui）+ 跑既有回归；改完 .ps1 必跑 scripts\_check-ps1-encoding.ps1。
   整行铺开的页面在 1280 / 1180 两个宽度各截一张核对版式。
4. 构建链路：frontend-build.ps1 → backend-build.ps1 → qms-server.ps1 -Action Start。
   演示数据：db-clear-complaints.ps1 -Force → seed-demo-ledger.ps1（40 张投诉，
   报表的统计与 KPI 要靠它才有非零数字）。
5. 收尾：更新 docs\code-inventory.md、docs\retrospective.md 与记忆文件（阶段表、脚本清单、
   新踩的坑），并给我简洁回执（改了哪些文件、断言数、遗留项）。

【已知约束/坑，别再踩一遍】
- .ps1 里**一个中文字符都不能有**（连注释也不行），中文只放 .json / .sql / .java / .mjs。
- 请求路径别漏 /api 前缀。
- PowerShell 5.1 的 Invoke-RestMethod 把 JSON 数组当单个对象（@(Invoke-RestMethod ...) 恒为 1 个
  元素 → 断言会静默假通过），必须先赋值再包 @()。
- psql -c 传中文会失败（SQL 保持 ASCII，或 -f 跑 UTF-8 文件）。
- 迁移只追加，V1 基线逐字节冻结；演示数据要走**真实 API** 造（阶段/状态由应用推进才自洽）。
- Office 产物一律**代码生成**（POI / PDFBox，仓库里没有模板文件）；PDF 内嵌中文字体
  （qms.report.pdf-font，回退 C:/Windows/Fonts/simhei.ttf）。
- **加权限码要连断言一起改**：V3 的管理员权限是当时的 CROSS JOIN 快照，新增码不会自动获得，
  必须在迁移里显式补 role_permission；同时 `verify-masterdata.ps1` 断言了权限总数。
- **附件写权限按 biz_type 判**（`AttachmentBizType.WRITE_PERMISSIONS`）：新类型要同时加
  LABELS、countParent 分支与写权限映射，漏一样就是越权或 403。
- `db-validate-migrations.ps1` **不要用 `2>&1` 调用**（会把 dropdb 的中文提示当错误中断脚本）。
- 前端 UI 脚本的 `data-*` 钩子要挂在**自己写的包装元素**上（Element Plus 会把属性转发到内层
  `<input>`，`[data-x] input` 匹配不到）。
```
