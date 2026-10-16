# QMS 生产部署方案

**适用系统**：QMS 问题解决管理系统（8D）
**部署形态**：Windows Server 原生部署 · 应用与数据库分离 · HTTPS
**文档日期**：2026-10-16
**状态**：方案已批准；阶段 A（应用侧改造）已完成，阶段 B/C/D 待实施

---

## 1. 背景与目标

QMS 已在本机跑通完整 8D 闭环（数据库迁移 V1–V21，API 断言 738 项、UI 断言 209 项全部通过）。本机目前的运行方式完全是为开发者准备的，直接搬到服务器**不可用**。已核实的事实：

- 单 fat jar `qms-api.jar`（约 70 MB），前端 `dist` 与数据库迁移脚本都打进 jar；前端用 hash 路由 + 相对 `/api` 路径，所以**不需要 nginx，也不需要 CORS**。
- 监听 **8080 明文 HTTP**；配置只来自 `config\.env`，以**进程级**环境变量注入。
- 启动方式是 `Start-Process java -jar`（隐藏窗口），是**登录会话的子进程**。
- **没有** Windows 服务、**没有** TLS、**没有**生产 profile 配置文件、**没有**部署文档。
- `application.yml` 里烤死了 `spring.profiles.active: local`，且 JWT 密钥带有开发用默认值。
- 迁移 V1–V21 由 Flyway 启动时自动执行；其中 **V9 是生产必需主数据**，9 个账号的口令是 `CHANGE_ME` 哨兵值，**生产环境下无法登录**。
- 唯一绝对路径硬编码：8D 报告 PDF 的中文字体回退到 `C:/Windows/Fonts/{simhei,msyh,Deng}.ttf`，**字体缺失时导出 PDF 直接报错**。
- 脚本目录里的路径配置全是开发机绝对路径，服务器安装不能依赖它。
- **无任何启动期外部网络调用**（杀毒、邮件仅在对应 provider 开启时按需连接）→ 适合离线部署。

**目标**：产出一套可重复执行的安装脚本 + 离线部署包 + 部署/运维/回滚手册，让运维能在一台干净的 Windows Server 上完成安装，其他同事用浏览器经 HTTPS 访问。

---

## 2. 已确认的决策

| 决策项 | 结论 |
|---|---|
| 部署拓扑 | **应用与数据库分离**（应用服务器 + 独立数据库服务器） |
| 服务化 | **注册为 Windows 服务**（开机自启、崩溃自动重启） |
| 传输安全 | **Spring Boot 自带 HTTPS**（应用直接监听 8443，不前置反向代理） |
| 交付形态 | **安装脚本 + 离线部署包 + 部署/运维/回滚手册** |
| DevOps 平台 | 一期**不引入**（公司 CI/CD 标准待向 IT 确认，二期再定） |
| 变更管理 | 走**简化流程**（登记 + 备份，不出正式工单） |

---

## 3. 目标架构

```
同事浏览器（内网）
      │  HTTPS :8443   TLS 1.2/1.3
      ▼
[应用服务器 Windows Server]   Windows 服务 "QMS"（WinSW 托管，开机自启 / 崩溃重启）
      │   C:\QMS\app\qms-api.jar            profile=prod + 外部配置
      │   C:\QMS\config\application-prod.yml
      │   C:\QMS\certs\qms.p12
      │   C:\QMS\data\attachments           C:\QMS\logs
      │  TCP :5432  密码认证 (scram-sha-256)
      ▼
[数据库服务器]  PostgreSQL 18   →   库 qms / schema qms / 专用角色 qms_app
```

一期为**单应用实例**（仅数据库分离）。多实例需要共享附件存储，**明确不做**。

---

## 4. 前提条件

### 4.1 应用服务器

| 项 | 要求 |
|---|---|
| 操作系统 | Windows Server 2019 / 2022，或 Windows 10/11 **专业版**（x64） |
| 权限 | 安装期需要**本地管理员** |
| 硬件 | ≥ 4 vCPU / ≥ 8 GB 内存；系统盘外 ≥ 100 GB（附件持续增长） |
| 网络 | **固定 IP + DNS 名**（证书 SAN 需要）；入站 **TCP 8443** 放通 |
| JDK | **JDK 21**（离线包内置 Temurin 21，或安装 MSI）；服务以**绝对路径**引用 `java.exe` |
| 中文字体 | 8D 报告 PDF 需要中文字体。**优先依赖服务器自带的 Windows 字体**（`simhei.ttf` / `Deng.ttf`），无需额外动作；缺失时（英文版 Windows Server 常见）才随包附**开源字体**并配置 `QMS_REPORT_PDF_FONT`。详见 4.4 |
| .NET | WinSW v2 需要 .NET Framework 4.6.1（Windows Server **自带**） |
| 时钟 | 启用 NTP 同步（JWT 过期时间、审计时间依赖它） |
| 外网 | **不需要**（走离线部署包） |

### 4.2 数据库服务器

| 项 | 要求 |
|---|---|
| 数据库 | PostgreSQL **18**（已装或新装） |
| 监听与认证 | `listen_addresses` 覆盖应用服务器可达地址；`pg_hba.conf` 放行应用服务器 IP + `scram-sha-256` 密码认证 |
| 库与角色 | 库 `qms`（**UTF8**）；**专用角色 `qms_app`（非 postgres 超级用户）**，拥有 `qms` schema（Flyway 首次建表需要 CREATE 权限） |
| 磁盘 | ≥ 200 GB，另留独立备份空间 |

### 4.3 网络与凭据

- 客户端 → 应用服务器：TCP **8443**
- 应用服务器 → 数据库服务器：TCP **5432**
- 需准备：`qms_app` 口令、JWT 密钥（**≥ 32 字节随机**）、管理员初始口令、证书口令
- 证书：公司 CA 签发的服务器证书（推荐）或自签证书（试运行）

### 4.4 报告 PDF 的中文字体（合规与格式约束）

**合规（重要）**：`simhei.ttf`（黑体）、`msyh.ttc`（微软雅黑）等是随 Windows 授权给**该台机器使用**的商业字体，**把字体文件复制进部署包分发到其他机器属于超授权范围**。因此：

- **首选**：只配置路径，**不复制文件** —— 依赖目标服务器自带的 Windows 字体。系统装了就无需任何额外动作。
- **必须随包携带时**（目标机没有中文字体）：只使用**可自由分发**的开源字体，例如思源黑体 / Noto Sans CJK、霞鹜文楷（**OFL 协议**），并把字体自带的许可证文本一并放进 `fonts/`。
- **绝不**把 Windows 自带商业字体放进部署包。

**格式约束（技术）**：PDF 由 PDFBox 的 `PDType0Font.load` 生成，只接受**单个、TrueType 轮廓（.ttf）**的字体文件：

| 格式 | 能否使用 | 说明 |
|---|---|---|
| `.ttf`（TrueType 轮廓） | ✅ | 唯一可用形态 |
| `.otf`（CFF 轮廓） | ❌ | PDFBox 无法嵌入 CFF 轮廓 |
| `.ttc`（字体集合） | ❌ | 当前实现直接拒绝并提示改路径 |
| 可变字体（文件名带 `VF`） | ⚠️ | 行为不确定，请改用**静态字重**版本 |

**现状提示**：现有回退列表里的 `msyh.ttf` 在 Windows 10/11 上**已不存在**（现为 `msyh.ttc`），因此实际可用的系统回退只有 `simhei.ttf` 与 `Deng.ttf` 两项。若目标服务器两者都没有，必须在部署包内提供开源 TTF 字体并设置 `QMS_REPORT_PDF_FONT` 指向其**绝对路径**。

---

## 5. 交付物

**离线部署包** `qms-deploy-<版本>-<日期>.zip`（服务器无需外网）：

```
qms-deploy/
  artifacts/  qms-api.jar                       # 构建产物
              jdk21/                            # 内置 JDK（离线必需，可换 MSI）
              winsw/qms-service.exe             # WinSW
  templates/  application-prod.yml.template
              qms-service.xml.template
  bin/        check-prereqs.ps1   install-qms.ps1   uninstall-qms.ps1
              upgrade-qms.ps1     new-cert.ps1      backup-qms.ps1
              health-check.ps1    reset-password.ps1
  sql/        db-init.sql                          # 建库 / 建角色 / 授权
  fonts/      （仅当目标机缺中文字体时放入 OFL 开源字体 + 其许可证文本；见 4.4）
  docs/       部署手册.md  运维手册.md  回滚手册.md  前提条件核对表.md
  SHA256SUMS.txt
```

全部 `.ps1` 遵循仓库既有约定：**纯 ASCII 或 UTF-8 BOM**（由 `_check-ps1-encoding.ps1` 守卫）、路径走**命名参数**、中文只出现在 `.md` / `.json`。

---

## 6. 需要新增 / 修改的内容

### A. 配置外部化 —— 无 Java 改动

- 新增 `deploy/templates/application-prod.yml.template`，安装时渲染为 `C:\QMS\config\application-prod.yml`，集中全部生产配置。
- 启动参数：`--spring.profiles.active=prod --spring.config.additional-location=file:./config/`
  - 命令行覆盖 jar 内烤死的 `local`；jar 里的 `application-local.yml`（含开发数据源与演示口令）**不会加载**。
  - 外部配置是**特定 profile 文件**，优先级高于 jar 内 `application.yml`，因此可直接覆盖带默认值的属性。
- 生产配置必填项：数据源 url/用户名/口令、`qms.jwt.secret`、`qms.storage.root`（**绝对路径**）、`server.ssl.*`、`server.shutdown: graceful`、邮件、杀毒、PDF 字体。

### B. HTTPS —— 无 Java 改动

- `server.port: 8443`、TLS 1.2/1.3、PKCS12 密钥库、`key-alias`。
- 生产**只监听 8443**，不再开 8080。
- `new-cert.ps1`：用 JDK 的 `keytool` 生成自签 PKCS12（**SAN 必须含 DNS 名 + IP**）；公司 CA 证书则提供导入 PFX 的手册步骤。

### C. Windows 服务 —— WinSW（Spring Boot 官方文档推荐方式）

- `qms-service.xml`：可执行文件指向 `java.exe` 绝对路径、参数带 `-jar` 与两个启动参数、工作目录设为安装根、**自动启动 + 延迟自启**（等数据库先起来）、**失败自动重启 3 次**、日志按大小时间滚动、停止超时、服务账号。
- 服务账号默认 **`NT AUTHORITY\LocalService`**（数据库走口令认证，不需要 Windows 身份；免密码、权限低）；公司有 AD 时也可换成**域服务账号**。
- 备选方案 **NSSM**（若运维更熟悉）。

### D. 目录与 ACL

- 建 `C:\QMS\{app,config,certs,data,logs,bin,docs}`。
- 授权：服务账号对 `data` / `logs` 为 **修改**，对 `app` / `config` / `certs` 为 **读取**；`config` 与 `certs` **拒绝普通用户读取**（仅服务账号 + Administrators）。

### E. 日志轮转 —— 小改动

新增 `logback-spring.xml`：滚动文件 `logs\qms-app.log`（按天 + 按大小，保留 30 天）+ 独立错误文件（保留 90 天），保留控制台输出。

### F. 账号初始化与口令 —— **唯一需要改 Java 的部分**

生产不设演示口令，9 个账号停在 `CHANGE_ME` → **无法登录**。新增**管理员口令 CLI**：

```
java -jar qms-api.jar --qms.admin.set-password=<用户名>
```

口令从环境变量 `QMS_NEW_PASSWORD` 读取（**不出现在命令行**，因此不进进程列表与命令历史）。安装时用它设置管理员口令；它同时是运维**重置口令**的正式入口。

另把 `application.yml` 的 `qms.jwt.secret` **默认值去掉改为必填**，杜绝"生产误用开发密钥"。

### G. 部署脚本

| 脚本 | 作用 |
|---|---|
| `check-prereqs.ps1` | 核对前提条件：OS / JDK / 字体 / 端口 / 目录 / 权限 / 到数据库的连通性 |
| `install-qms.ps1` | 分阶段 `-Stage Prepare/Service/Firewall/All`：建目录 + ACL → 落配置 → 装服务 → 防火墙规则 → 健康检查 |
| `uninstall-qms.ps1` | 停服务、卸载服务、保留数据（可选删除） |
| `upgrade-qms.ps1` | 备份 → 停服务 → 换 jar → 启动 → 校验 → **失败自动回滚** |
| `new-cert.ps1` | 生成自签 PKCS12（含 SAN），或导入公司 PFX |
| `backup-qms.ps1` | 备份附件目录（+ 提示数据库端 `pg_dump` 命令） |
| `health-check.ps1` | 探测 `https://localhost:8443/actuator/health`（自签证书需忽略校验） |
| `reset-password.ps1` | 包装第 F 项的口令 CLI |

### H. 文档

`部署手册.md`（前提核对表 + 逐步命令 + 截图位）、`运维手册.md`（启停 / 日志 / 备份 / 监控 / 口令重置 / 账号开通）、`回滚手册.md`。

---

## 7. 部署步骤（安装手册主干）

1. 应用服务器跑 `check-prereqs.ps1`，按报告补齐。
2. **数据库服务器**执行 `sql/db-init.sql`：建库 `qms`（UTF8）、建角色 `qms_app`、授权，并给出 `pg_hba.conf` 提示。
3. 应用服务器解开离线包；`new-cert.ps1` 生成或导入证书。
4. 由模板生成 `C:\QMS\config\application-prod.yml`（填数据库地址与口令、JWT 密钥、证书口令、附件路径、SMTP / 杀毒配置）。
5. `install-qms.ps1 -Stage Prepare`：建目录 + ACL + 落配置。
6. `install-qms.ps1 -Stage Service`：安装并启动服务。
7. 查看日志，确认 Flyway 首次迁移到 **V21** 成功。
8. `reset-password.ps1` 设置管理员口令；登录后在系统管理里开通其他账号。
9. `install-qms.ps1 -Stage Firewall`：放通 8443。
10. 冒烟：`health-check.ps1` + 浏览器登录 + 建单 + 传附件 + 导出 Word / PDF。
11. **重启服务器**验证服务自启（这是"企业级"与"手工启动"的分水岭）。

---

## 8. 安全加固清单

- JWT 密钥必填且 ≥ 32 字节随机；数据库使用**专用最小权限角色**（非 `postgres` 超级用户）。
- `config` 与 `certs` 目录 ACL 收紧。
- 生产天然关闭开发数据源与演示口令（profile 隔离已做到）。
- TLS 1.2/1.3，禁用弱协议；生产只开 8443。
- `/actuator/health` 与 `/actuator/info` 当前是**匿名可访问**（仅暴露 health/info，可接受）；如需进一步收敛可加 IP 白名单。
- 口令策略：登录失败 **5 次锁定 15 分钟**（系统已有）；管理员口令由安装方设定，**不使用默认口令**。

---

## 9. 运维：备份 / 升级 / 回滚 / 监控

- **备份**：数据库端 `pg_dump`（计划任务，每日，保留多份）；应用端附件目录由 `backup-qms.ps1` 同步到备份共享；`config` 与 `certs` 单独加密留存。
- **升级**：`upgrade-qms.ps1` = 备份 → 停服务 → 换 jar → 启动 → 健康检查；Flyway 自动迁移。
- **回滚**：迁移**只追加**（全部是加列 / 加表），旧 jar 通常仍能跑新库，所以**优先应用回滚**（换回旧 jar）；稳妥回滚 = 还原升级前的数据库备份 + 换回旧 jar。
- **监控**：`/actuator/health` 由计划任务定时探测并告警；错误日志单独留一份便于值守。
- **日志**：应用日志轮转保留 30 天；服务包装器另有自己的日志，与应用日志分离（便于区分"启动失败"与"业务错误"）。

---

## 10. 发布管理与演进路线（迭代发布 / DevOps）

### 版本与制品规范

- 语义化版本 `MAJOR.MINOR.PATCH`；每次发布打 **git tag** + 维护 `CHANGELOG.md`。
- **制品不可变**：构建产出 `qms-api-<版本>.jar` + `SHA256`；**只从制品库取，不在服务器上现场构建**。
- 一期制品库 = 归档目录 / 只读共享；二期接 Nexus / Artifactory。

### 环境分级

`DEV（开发）→ UAT（试运行，至少 1 台）→ PROD`。**禁止 DEV 直连 PROD 库**。

### 发布流程（脚本版，本期落地）

变更单 → 备份（数据库 dump + 附件）→ 停服 → 换 jar → 启服 → 健康检查 → 冒烟 → 归档。

### 数据库兼容原则（决定能否平滑回滚）

- Flyway **只追加**；**只加列不删列**；破坏性变更**分两次发布**（先加新列并用，下个版本再删旧列）。
- 发布前在**临时库**重放校验迁移脚本。
- 回滚优先应用回滚；数据回滚 = 还原备份（代价高，靠上面的兼容原则避免）。

### 演进路线

| 阶段 | 触发条件 | 做什么 | 引入平台？ |
|---|---|---|---|
| 一（本期） | 一期上线 | 脚本化发布 + 版本 / 制品规范 + UAT 试运行 | **否** |
| 二 | 有 UAT / 第二环境、团队 >1 人 | 接**公司既有 CI**：自动构建 + 跑 947 条断言 + 制品入库 + 触发部署脚本 | 复用公司既有，**不新引入** |
| 三 | 多实例 / 合规要求高 | 容器化 + K8s，或 Ansible / Octopus 部署编排 | 视公司标准 |

**平台选型原则**：先问 IT **公司现有标准栈**，**优先复用**。猪齿鱼（Choerodon）、云效、CODING 属"团队级 DevOps 平台"，**猪齿鱼本身跑在 K8s 上**，对 Windows 原生单应用是过度设计，且会造成"第二套 DevOps"，安全 / 合规 / 运维都不认。**故本期不引入。**

**已具备的 CI 友好资产**：可重复构建（Maven + npm）、**947 条自动化断言**、单 jar 制品、部署脚本 —— **部署脚本就是流水线的最后一段**，将来接入无需重构。

### 合规提醒（IATF 16949）

QMS 承载 8D，属 **IATF 16949** 要求的质量工具；OEM 客户审核会查**审计追溯与数据留存**。"变更可追溯、审计日志完整、备份可恢复"是**合规要求**，应纳入验收清单。

---

## 11. 验收

在**一台干净 Windows Server**（或新虚拟机）上端到端走一遍：

1. `check-prereqs.ps1` → 全部通过。
2. 安装完成后 `Get-Service QMS` = Running，**重启机器后仍 Running**。
3. `health-check.ps1` 返回 `UP`。
4. 浏览器访问 `https://<主机>/` 正常打开（证书受信，或已安装 CA）。
5. 管理员登录 → 建一张投诉 → 上传附件 → 走 D2 → **导出 Word 与 PDF 均成功**（验证中文字体前提）。
6. **另一台电脑**用浏览器访问同一地址成功（验证"给其他用户使用"）。
7. 演练一次 `upgrade-qms.ps1` 与 `backup-qms.ps1`。

---

## 12. 待确认项（需拍板）

| 编号 | 事项 | 建议 |
|---|---|---|
| 1 | TLS 证书来源 | 公司 CA 签发的服务器证书（推荐）；试运行可先用自签 |
| 2 | 数据库由谁建库 / 授权 | 提供 SQL 脚本由 DBA 执行（贴合分离部署） |
| 3 | 杀毒 | 接 **ClamAV**（已有可插拔适配器）或接受不扫描的残余风险 |
| 4 | 邮件 | 接**公司 SMTP 中继**（报告真发信）或继续记录日志不真发 |
| 5 | 首次登录强制改密 | 建议**二期**；本期用安装方设定的强口令 + 口令重置工具兜住 |
| 6 | 数据库连接是否加密 | 视公司要求决定是否启用 `sslmode=require` |

---

## 13. 明确不在本期

- 多应用实例 / 负载均衡（需共享附件存储，一期单实例）
- SSO / OAuth2 对接（认证提供方仍为空实现）
- 高保真 Office 服务器端转换（需服务器安装 LibreOffice，本机未装）
- 自动化 CI/CD 与镜像化发布（本期走离线包 + 脚本）

---

## 14. 实施进展

### 阶段 A：应用侧改造 —— **已完成（2026-10-16）**

| 文件 | 改动 |
|---|---|
| `backend/src/main/resources/application.yml` | JWT 密钥去掉默认值，改为必填 |
| `backend/src/main/resources/logback-spring.xml` | **新增**：日志按天 + 按大小滚动，错误日志分离 |
| `backend/src/main/java/.../auth/AdminPasswordCli.java` | **新增**：管理员口令 CLI |
| `backend/src/main/java/.../auth/mapper/AuthMapper.java` | 新增 `clearLock`（重置换口令时清锁定，不伪造登录时间） |
| `deploy/templates/application-prod.yml.template` | **新增**：生产配置模板 |
| `config/.env.example` | 修正 SMTP 变量名（原写的与代码实际读取的不一致） |

**实测结果**：

- 口令 CLI 四条路径退出码正确（成功 / 缺环境变量 / 未知用户 / 口令过短）；改密后**新口令登录成功、旧口令被拒**。
- JWT 密钥缺失时**启动即失败**并给出明确错误，不再静默使用开发密钥。
- prod profile + 外部配置 + 自签证书 → **8443 HTTPS 启动成功**，健康检查返回 200。
- 日志轮转文件正常落盘。
- 回归测试 `verify-auth` **21/21 通过**。

### 阶段 B / C / D —— 待实施

- **阶段 B**：部署脚本 + WinSW 配置 + `db-init.sql`
- **阶段 C**：文档 + 离线包打包脚本
- **阶段 D**：干净环境端到端验收
