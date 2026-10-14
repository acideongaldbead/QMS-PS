-- ===========================================================================
-- QMS 问题解决管理系统 · 数据字典与 ER 设计 - PostgreSQL DDL
-- ===========================================================================
-- 需求来源 : 《QMS-问题解决管理系统采购需求- V8》（2026-09-22）及配套文件 XTE-0071 8D Problem Report、XTE-0037 3x5Why、XTE-0038 客诉登记表
-- 数据库   : PostgreSQL 12+（需求文档 3.15 指定为 PG 库）
-- 生成日期 : 2026-09-24
-- 生成方式 : gen_postgres_ddl.ps1 读 datadict_data.json 自动生成，请勿手工修改本文件
--
-- 命名约定
--   Schema      : qms
--   表名        : 小写下划线单数（report_8d），不加引号；逻辑名见各表 COMMENT
--   列名        : 小写下划线（complaint_id）
--   主键        : <表名>_id；业务单据用 varchar 保留编号前导零，配置类实体用 bigint identity
--   约束前缀    : pk_ / fk_ / uq_ / ck_ / idx_
--
-- 设计约定
--   * 所有表含审计字段 created_at / created_by / updated_at / updated_by / is_deleted；
--     表内已存在同名列时不重复添加（如 Complaint.created_by 既是业务字段「发起人」也是审计字段）。
--   * 字典类字段在业务表只存 code，展示名取自字典表，不硬编码中文，便于中英文切换（3.17）。
--   * 外键统一在全部建表后以 ALTER TABLE 添加，避免建表顺序问题。
--   * 删除策略：组合关系（单据→其明细）用 CASCADE；主数据/人员引用用 RESTRICT；
--     自关联且可空用 SET NULL。
--   * 附件、审批等对多类单据的关联用 biz_type + biz_id 多态关联，不建物理外键。
--   * CHECK 约束均为建议项，需业务方确认后启用。
-- ===========================================================================

CREATE SCHEMA IF NOT EXISTS qms;
SET search_path TO qms, public;

-- 模糊检索（3.11 要求可模糊检索所有问题解决数据）。
-- 注意：PostgreSQL 内置全文检索对中文分词支持有限，如需中文分词建议另装 zhparser，
-- 本脚本先用 pg_trgm 三元组索引支撑 LIKE / similarity 查询。
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
-- 通用 updated_at 触发器
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- 业务编号序列（解决并发下 C+4 位年+5 位序号 的取值安全）
-- 用法：SELECT next_document_no('C', 'COMPLAINT');  -- 返回 C202600722
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS document_sequence (
    seq_key      varchar(32)  NOT NULL,
    last_value   bigint       NOT NULL DEFAULT 0,
    updated_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_document_sequence PRIMARY KEY (seq_key)
);
COMMENT ON TABLE document_sequence IS '业务编号序列表：按「前缀+年度+业务类型」维护流水号，配合 next_document_no() 保证并发唯一';

CREATE OR REPLACE FUNCTION next_document_no(p_prefix varchar, p_biz varchar, p_width int DEFAULT 5)
RETURNS varchar AS $$
DECLARE
    v_year  varchar(4) := to_char(now(), 'YYYY');
    v_key   varchar(32) := p_biz || '-' || v_year;
    v_next  bigint;
BEGIN
    INSERT INTO document_sequence (seq_key, last_value)
    VALUES (v_key, 1)
    ON CONFLICT (seq_key) DO UPDATE SET last_value = document_sequence.last_value + 1,
                                        updated_at = now()
    RETURNING last_value INTO v_next;
    RETURN p_prefix || v_year || lpad(v_next::text, p_width, '0');
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION next_document_no(varchar, varchar, int) IS '生成业务单据编号：前缀+4位年份+定长流水号，如 C202600722（共 10 位）。编号规则已确认（Q-13）：统一采用 C+4 位年+5 位序号，与需求文档示例一致。';

-- ===========================================================================
-- 建表
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- customer   客户主数据   [主数据]
-- 来源：3.14.2 (SAP)
-- 来自 SAP 的客户主数据，供下拉选择与模糊查询。
-- ---------------------------------------------------------------------------
CREATE TABLE customer (
    customer_code            varchar(32) NOT NULL,
    customer_name            varchar(255) NOT NULL,
    country                  varchar(64),
    city                     varchar(64),
    street_address           varchar(255),
    synced_at                timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_customer PRIMARY KEY (customer_code)
);
COMMENT ON TABLE customer IS '客户主数据 | 来自 SAP 的客户主数据，供下拉选择与模糊查询。';
COMMENT ON COLUMN customer.customer_code IS '客户编号 | SAP 原值，保持源系统编码 | PK';
COMMENT ON COLUMN customer.customer_name IS '客户名称 | 同步自 SAP';
COMMENT ON COLUMN customer.country IS '国家 | 同步自 SAP';
COMMENT ON COLUMN customer.city IS '城市 | 同步自 SAP';
COMMENT ON COLUMN customer.street_address IS '街道地址 | 同步自 SAP';
COMMENT ON COLUMN customer.synced_at IS '同步时间 | 增量同步时间戳';
COMMENT ON COLUMN customer.is_active IS '是否启用 | 停用不删除，历史数据仍可展示';
COMMENT ON COLUMN customer.created_at IS '审计：创建时间';
COMMENT ON COLUMN customer.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN customer.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN customer.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN customer.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- contact_person   客户联系人   [主数据]
-- 来源：3.1.3
-- 客户联系人主数据，可与系统内新增并与客户挂钩。
-- ---------------------------------------------------------------------------
CREATE TABLE contact_person (
    contact_id               varchar(32) NOT NULL,
    customer_code            varchar(32) NOT NULL,
    contact_name             varchar(128) NOT NULL,
    email                    varchar(255),
    phone                    varchar(64),
    source_type              varchar(16),
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_contact_person PRIMARY KEY (contact_id)
);
COMMENT ON TABLE contact_person IS '客户联系人 | 客户联系人主数据，可与系统内新增并与客户挂钩。';
COMMENT ON COLUMN contact_person.contact_id IS '联系人ID | 系统生成 | PK';
COMMENT ON COLUMN contact_person.customer_code IS '客户编号 | 与 Quality Partner 挂钩 | FK';
COMMENT ON COLUMN contact_person.contact_name IS '姓名 | 联系人姓名';
COMMENT ON COLUMN contact_person.email IS '邮箱 | 8D 报告发送时自动填充为收件人';
COMMENT ON COLUMN contact_person.phone IS '电话 | 联系电话';
COMMENT ON COLUMN contact_person.source_type IS '来源 | 主数据同步 / 系统内新增';
COMMENT ON COLUMN contact_person.is_active IS '是否启用 | 停用不删除';
COMMENT ON COLUMN contact_person.created_at IS '审计：创建时间';
COMMENT ON COLUMN contact_person.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN contact_person.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN contact_person.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN contact_person.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- ship_to_sold_to   收货/售达方主数据   [主数据]
-- 来源：3.1.3 (SAP)
-- 来自 SAP 客户主数据的 Ship-To / Sold-to 工厂主数据。
-- ---------------------------------------------------------------------------
CREATE TABLE ship_to_sold_to (
    ship_to_code             varchar(32) NOT NULL,
    customer_code            varchar(32) NOT NULL,
    ship_to_name             varchar(128) NOT NULL,
    ship_to_type             varchar(16),
    synced_at                timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_ship_to_sold_to PRIMARY KEY (ship_to_code)
);
COMMENT ON TABLE ship_to_sold_to IS '收货/售达方主数据 | 来自 SAP 客户主数据的 Ship-To / Sold-to 工厂主数据。';
COMMENT ON COLUMN ship_to_sold_to.ship_to_code IS '工厂编号 | SAP 客户主数据原值 | PK';
COMMENT ON COLUMN ship_to_sold_to.customer_code IS '客户编号 | 所属客户，用于选项过滤 | FK';
COMMENT ON COLUMN ship_to_sold_to.ship_to_name IS '工厂名称 | 如通用武汉工厂、通用烟台工厂、深圳华为';
COMMENT ON COLUMN ship_to_sold_to.ship_to_type IS '类型 | Ship-To / Sold-to';
COMMENT ON COLUMN ship_to_sold_to.synced_at IS '同步时间 | 同步时间';
COMMENT ON COLUMN ship_to_sold_to.is_active IS '是否启用 | 停用不删除';
COMMENT ON COLUMN ship_to_sold_to.created_at IS '审计：创建时间';
COMMENT ON COLUMN ship_to_sold_to.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN ship_to_sold_to.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN ship_to_sold_to.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN ship_to_sold_to.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- employee   人员主数据   [主数据]
-- 来源：3.14.2 (MDM/HR)
-- 从 HR/MDM 同步的组织架构与员工信息，是全系统人员选择的数据来源。
-- ---------------------------------------------------------------------------
CREATE TABLE employee (
    employee_id              varchar(32) NOT NULL,
    name                     varchar(128) NOT NULL,
    email                    varchar(255) NOT NULL,
    dept_l1                  varchar(128),
    dept_l2                  varchar(128),
    line_manager_id          varchar(32),
    synced_at                timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_employee PRIMARY KEY (employee_id)
);
COMMENT ON TABLE employee IS '人员主数据 | 从 HR/MDM 同步的组织架构与员工信息，是全系统人员选择的数据来源。';
COMMENT ON COLUMN employee.employee_id IS '员工ID | HR 系统原值 | PK';
COMMENT ON COLUMN employee.name IS '姓名 | 同步自 HR';
COMMENT ON COLUMN employee.email IS '邮箱 | 同步自 HR，用于通知与 SSO 绑定';
COMMENT ON COLUMN employee.dept_l1 IS '一级部门 | 同步自 HR';
COMMENT ON COLUMN employee.dept_l2 IS '二级部门 | 同步自 HR；数据行级权限隔离依据';
COMMENT ON COLUMN employee.line_manager_id IS '直线经理 | 自关联；用于审批流升级 | FK';
COMMENT ON COLUMN employee.synced_at IS '同步时间 | 同步时间';
COMMENT ON COLUMN employee.is_active IS '是否启用 | 离职停用不删除';
COMMENT ON COLUMN employee.created_at IS '审计：创建时间';
COMMENT ON COLUMN employee.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN employee.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN employee.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN employee.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- production_master   生产主数据   [主数据]
-- 来源：3.14.2 (MES)
-- 来自 MES 的工序、工序组、生产线机台主数据。
-- ---------------------------------------------------------------------------
CREATE TABLE production_master (
    pm_id                    varchar(32) NOT NULL,
    pm_type                  varchar(16) NOT NULL,
    code                     varchar(32) NOT NULL,
    name                     varchar(128) NOT NULL,
    parent_id                varchar(32),
    synced_at                timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_production_master PRIMARY KEY (pm_id)
);
COMMENT ON TABLE production_master IS '生产主数据 | 来自 MES 的工序、工序组、生产线机台主数据。';
COMMENT ON COLUMN production_master.pm_id IS '记录ID | MES 原值 | PK';
COMMENT ON COLUMN production_master.pm_type IS '类型 | 工序 / 工序组 / 生产线机台';
COMMENT ON COLUMN production_master.code IS '编码 | MES 编码';
COMMENT ON COLUMN production_master.name IS '名称 | 名称';
COMMENT ON COLUMN production_master.parent_id IS '上级 | 自关联，表达工序组-工序层级 | FK';
COMMENT ON COLUMN production_master.synced_at IS '同步时间 | 同步时间';
COMMENT ON COLUMN production_master.is_active IS '是否启用 | 停用不删除';
COMMENT ON COLUMN production_master.created_at IS '审计：创建时间';
COMMENT ON COLUMN production_master.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN production_master.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN production_master.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN production_master.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- master_data_item   QMS平台主数据项   [主数据]
-- 来源：3.14.2
-- QMS 平台自有的统一主数据表，供所有子系统共用；高级管理员可配置。自关联表达层级。
-- ---------------------------------------------------------------------------
CREATE TABLE master_data_item (
    md_id                    bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    md_type                  varchar(32) NOT NULL,
    code                     varchar(32) NOT NULL,
    name_cn                  varchar(128) NOT NULL,
    name_en                  varchar(128),
    parent_id                bigint,
    source_system            varchar(16) NOT NULL,
    sort_order               integer,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_master_data_item PRIMARY KEY (md_id),
    CONSTRAINT uq_master_data_item_code UNIQUE (code)
);
COMMENT ON TABLE master_data_item IS 'QMS平台主数据项 | QMS 平台自有的统一主数据表，供所有子系统共用；高级管理员可配置。自关联表达层级。';
COMMENT ON COLUMN master_data_item.md_id IS '主数据ID | 自增 | PK';
COMMENT ON COLUMN master_data_item.md_type IS '主数据类型 | 投诉类型 / 优先级 / 失效位置 / 失效代码 / 子分部 / 文件类型 / 责任组织 等';
COMMENT ON COLUMN master_data_item.code IS '编码 | 业务表统一存 code；同类型下唯一';
COMMENT ON COLUMN master_data_item.name_cn IS '名称(中) | 中文展示名';
COMMENT ON COLUMN master_data_item.name_en IS '名称(英) | 英文展示名，对应中英文切换';
COMMENT ON COLUMN master_data_item.parent_id IS '上级ID | 自关联，支持多级主数据 | FK';
COMMENT ON COLUMN master_data_item.source_system IS '来源系统 | QMS / SAP / MDM / MES；外部来源不可在 QMS 编辑';
COMMENT ON COLUMN master_data_item.sort_order IS '排序号 | 下拉展示顺序';
COMMENT ON COLUMN master_data_item.is_active IS '是否启用 | 停用不影响历史数据展示';
COMMENT ON COLUMN master_data_item.created_at IS '审计：创建时间';
COMMENT ON COLUMN master_data_item.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN master_data_item.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN master_data_item.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN master_data_item.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- failure_type   失效类型（三级）   [主数据]
-- 来源：3.3 / 内嵌电子表格
-- Failure_Type_L1/L2/L3 三级失效类型主数据，管理员可维护。
-- ---------------------------------------------------------------------------
CREATE TABLE failure_type (
    failure_type_id          bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    level_no                 smallint NOT NULL,
    code                     varchar(32) NOT NULL,
    name                     varchar(128) NOT NULL,
    parent_id                bigint,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_failure_type PRIMARY KEY (failure_type_id),
    CONSTRAINT uq_failure_type_code UNIQUE (code)
);
COMMENT ON TABLE failure_type IS '失效类型（三级） | Failure_Type_L1/L2/L3 三级失效类型主数据，管理员可维护。';
COMMENT ON COLUMN failure_type.failure_type_id IS '失效类型ID | 自增 | PK';
COMMENT ON COLUMN failure_type.level_no IS '层级 | 1=L1 / 2=L2 / 3=L3';
COMMENT ON COLUMN failure_type.code IS '编码 | 如 2 / 2a / 2aa（示例：2 - Assembly related → 2a - Bond and wire → 2aa - Lifted ball bond）';
COMMENT ON COLUMN failure_type.name IS '名称 | 失效类型名称，建议双语';
COMMENT ON COLUMN failure_type.parent_id IS '上级ID | 自关联；L1 的上级为空，L2 上级须为 L1 | FK';
COMMENT ON COLUMN failure_type.is_active IS '是否启用 | 管理员可维护，停用不影响历史数据';
COMMENT ON COLUMN failure_type.created_at IS '审计：创建时间';
COMMENT ON COLUMN failure_type.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN failure_type.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN failure_type.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN failure_type.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- status_code   状态码字典   [主数据]
-- 来源：3.1.2 等
-- 统一状态字典，避免状态中文硬编码在各业务表。
-- ---------------------------------------------------------------------------
CREATE TABLE status_code (
    status_code              varchar(32) NOT NULL,
    entity_name              varchar(32) NOT NULL,
    name_cn                  varchar(64) NOT NULL,
    name_en                  varchar(64),
    sort_order               integer,
    is_final                 boolean,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_status_code PRIMARY KEY (status_code)
);
COMMENT ON TABLE status_code IS '状态码字典 | 统一状态字典，避免状态中文硬编码在各业务表。';
COMMENT ON COLUMN status_code.status_code IS '状态码 | 如 REG_STARTED 登记-已启动、VER_SCHEDULED 验证-已排期 | PK';
COMMENT ON COLUMN status_code.entity_name IS '所属实体 | Complaint / Report8D / CorrectiveAction 等';
COMMENT ON COLUMN status_code.name_cn IS '名称(中) | 中文展示名';
COMMENT ON COLUMN status_code.name_en IS '名称(英) | 英文展示名';
COMMENT ON COLUMN status_code.sort_order IS '排序号 | 流程先后顺序';
COMMENT ON COLUMN status_code.is_final IS '是否终态 | 标识是否为终态（如已结案）';
COMMENT ON COLUMN status_code.created_at IS '审计：创建时间';
COMMENT ON COLUMN status_code.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN status_code.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN status_code.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN status_code.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- role   角色   [平台权限]
-- 来源：3.12
-- 预设标准角色与自定义角色。
-- ---------------------------------------------------------------------------
CREATE TABLE role (
    role_id                  bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    role_name                varchar(64) NOT NULL,
    role_type                varchar(16) NOT NULL,
    dept_code                varchar(128),
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_role PRIMARY KEY (role_id)
);
COMMENT ON TABLE role IS '角色 | 预设标准角色与自定义角色。';
COMMENT ON COLUMN role.role_id IS '角色ID | 自增 | PK';
COMMENT ON COLUMN role.role_name IS '角色名称 | 如销售质量、质量工程师、审核员、管理员';
COMMENT ON COLUMN role.role_type IS '角色类型 | 预设 / 自定义（按人员或部门）';
COMMENT ON COLUMN role.dept_code IS '关联部门 | 自定义角色可按部门绑定';
COMMENT ON COLUMN role.is_active IS '是否启用 | 停用后不再分配';
COMMENT ON COLUMN role.created_at IS '审计：创建时间';
COMMENT ON COLUMN role.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN role.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN role.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN role.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- permission   权限   [平台权限]
-- 来源：3.12
-- 权限项定义，支持四级粒度。
-- ---------------------------------------------------------------------------
CREATE TABLE permission (
    permission_id            bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    permission_code          varchar(64) NOT NULL,
    permission_name          varchar(64) NOT NULL,
    permission_level         varchar(16) NOT NULL,
    module_code              varchar(32),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_permission PRIMARY KEY (permission_id)
);
COMMENT ON TABLE permission IS '权限 | 权限项定义，支持四级粒度。';
COMMENT ON COLUMN permission.permission_id IS '权限ID | 自增 | PK';
COMMENT ON COLUMN permission.permission_code IS '权限编码 | 如 complaint:register、report:send';
COMMENT ON COLUMN permission.permission_name IS '权限名称 | 如登记、编辑、删除、审批、查看报表';
COMMENT ON COLUMN permission.permission_level IS '权限级别 | 系统级 / 模块级 / 功能按钮级 / 数据行级';
COMMENT ON COLUMN permission.module_code IS '所属模块 | 模块级权限的归属模块';
COMMENT ON COLUMN permission.created_at IS '审计：创建时间';
COMMENT ON COLUMN permission.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN permission.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN permission.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN permission.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- role_permission   角色权限关联   [平台权限]
-- 来源：3.12
-- 角色与权限的多对多关联。
-- ---------------------------------------------------------------------------
CREATE TABLE role_permission (
    role_permission_id       bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    role_id                  bigint NOT NULL,
    permission_id            bigint NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_role_permission PRIMARY KEY (role_permission_id),
    CONSTRAINT uq_role_permission UNIQUE (role_id, permission_id)
);
COMMENT ON TABLE role_permission IS '角色权限关联 | 角色与权限的多对多关联。';
COMMENT ON COLUMN role_permission.role_permission_id IS '关联ID | 自增 | PK';
COMMENT ON COLUMN role_permission.role_id IS '角色ID | 角色 | FK';
COMMENT ON COLUMN role_permission.permission_id IS '权限ID | 权限 | FK';
COMMENT ON COLUMN role_permission.created_at IS '审计：创建时间';
COMMENT ON COLUMN role_permission.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN role_permission.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN role_permission.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN role_permission.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- user_role   用户角色关联   [平台权限]
-- 来源：3.12
-- 用户与角色的多对多关联。
-- ---------------------------------------------------------------------------
CREATE TABLE user_role (
    user_role_id             bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    employee_id              varchar(32) NOT NULL,
    role_id                  bigint NOT NULL,
    effective_from           timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_user_role PRIMARY KEY (user_role_id),
    CONSTRAINT uq_user_role UNIQUE (employee_id, role_id)
);
COMMENT ON TABLE user_role IS '用户角色关联 | 用户与角色的多对多关联。';
COMMENT ON COLUMN user_role.user_role_id IS '关联ID | 自增 | PK';
COMMENT ON COLUMN user_role.employee_id IS '员工ID | 用户 | FK';
COMMENT ON COLUMN user_role.role_id IS '角色ID | 角色 | FK';
COMMENT ON COLUMN user_role.effective_from IS '生效时间 | 权限变更即时生效并留痕';
COMMENT ON COLUMN user_role.created_at IS '审计：创建时间';
COMMENT ON COLUMN user_role.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN user_role.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN user_role.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN user_role.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- audit_log   审计日志   [平台权限]
-- 来源：3.16
-- 登录、关键数据修改、报告导出等操作的审计日志，保留至少 3 年。
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    log_id                   bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    operator_id              varchar(32) NOT NULL,
    action_type              varchar(32) NOT NULL,
    biz_type                 varchar(32),
    biz_id                   varchar(32),
    before_value             text,
    after_value              text,
    ip_address               varchar(64),
    created_at               timestamptz NOT NULL DEFAULT now(),
    retain_until             date,
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_audit_log PRIMARY KEY (log_id)
);
COMMENT ON TABLE audit_log IS '审计日志 | 登录、关键数据修改、报告导出等操作的审计日志，保留至少 3 年。';
COMMENT ON COLUMN audit_log.log_id IS '日志ID | 自增 | PK';
COMMENT ON COLUMN audit_log.operator_id IS '操作人 | 操作人 | FK';
COMMENT ON COLUMN audit_log.action_type IS '操作类型 | 登录 / 修改 / 导出 / 删除 / 审批 等';
COMMENT ON COLUMN audit_log.biz_type IS '业务类型 | 涉及的业务对象';
COMMENT ON COLUMN audit_log.biz_id IS '业务ID | 业务主键';
COMMENT ON COLUMN audit_log.before_value IS '变更前值 | 关键字段修改前的值';
COMMENT ON COLUMN audit_log.after_value IS '变更后值 | 关键字段修改后的值';
COMMENT ON COLUMN audit_log.ip_address IS 'IP地址 | 来源 IP';
COMMENT ON COLUMN audit_log.created_at IS '操作时间 | 操作时间';
COMMENT ON COLUMN audit_log.retain_until IS '保留至 | 至少 3 年，用于归档策略';
COMMENT ON COLUMN audit_log.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN audit_log.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN audit_log.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN audit_log.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- system_announcement   系统公告   [平台权限]
-- 来源：3.0
-- 首页工作台展示的系统公告。
-- ---------------------------------------------------------------------------
CREATE TABLE system_announcement (
    announcement_id          bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    title                    varchar(255) NOT NULL,
    content                  text NOT NULL,
    publish_status           varchar(16) NOT NULL,
    published_by             varchar(32),
    published_at             timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_system_announcement PRIMARY KEY (announcement_id)
);
COMMENT ON TABLE system_announcement IS '系统公告 | 首页工作台展示的系统公告。';
COMMENT ON COLUMN system_announcement.announcement_id IS '公告ID | 自增 | PK';
COMMENT ON COLUMN system_announcement.title IS '标题 | 公告标题';
COMMENT ON COLUMN system_announcement.content IS '内容 | 富文本，支持附件';
COMMENT ON COLUMN system_announcement.publish_status IS '发布状态 | 草稿 / 已发布 / 已下架';
COMMENT ON COLUMN system_announcement.published_by IS '发布人 | 发布人 | FK';
COMMENT ON COLUMN system_announcement.published_at IS '发布时间 | 首页按发布时间倒序展示';
COMMENT ON COLUMN system_announcement.created_at IS '审计：创建时间';
COMMENT ON COLUMN system_announcement.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN system_announcement.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN system_announcement.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN system_announcement.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- notification_rule   通知规则   [通知集成]
-- 来源：3.13
-- TPT 目标与提醒规则配置。
-- ---------------------------------------------------------------------------
CREATE TABLE notification_rule (
    rule_id                  bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    milestone_code           varchar(16) NOT NULL,
    target_days              integer NOT NULL,
    priority_scope           varchar(64),
    remind_before_days       integer,
    escalate_to_id           varchar(32),
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_notification_rule PRIMARY KEY (rule_id)
);
COMMENT ON TABLE notification_rule IS '通知规则 | TPT 目标与提醒规则配置。';
COMMENT ON COLUMN notification_rule.rule_id IS '规则ID | 自增 | PK';
COMMENT ON COLUMN notification_rule.milestone_code IS '里程碑 | FA / D3 / D8 等；如样品登记后 5 个工作日完成 FA';
COMMENT ON COLUMN notification_rule.target_days IS '目标工作日 | TPT target 天数；报表样例含 Target(3D)=3 天、Target(8D)=6 天';
COMMENT ON COLUMN notification_rule.priority_scope IS '适用优先级 | 按投诉优先级差异化配置';
COMMENT ON COLUMN notification_rule.remind_before_days IS '提前提醒天数 | 到期前多少天开始提醒';
COMMENT ON COLUMN notification_rule.escalate_to_id IS '升级对象 | 超期升级通知对象 | FK';
COMMENT ON COLUMN notification_rule.is_active IS '是否启用 | 规则启停';
COMMENT ON COLUMN notification_rule.created_at IS '审计：创建时间';
COMMENT ON COLUMN notification_rule.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN notification_rule.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN notification_rule.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN notification_rule.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- notification   通知记录   [通知集成]
-- 来源：3.13
-- 任务分配、审批请求、超期提醒的通知发送记录。
-- ---------------------------------------------------------------------------
CREATE TABLE notification (
    notification_id          bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    biz_type                 varchar(32) NOT NULL,
    biz_id                   varchar(32) NOT NULL,
    recipient_id             varchar(32) NOT NULL,
    channel                  varchar(16) NOT NULL,
    template_code            varchar(32),
    send_status              varchar(16) NOT NULL,
    sent_at                  timestamptz,
    error_msg                text,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_notification PRIMARY KEY (notification_id)
);
COMMENT ON TABLE notification IS '通知记录 | 任务分配、审批请求、超期提醒的通知发送记录。';
COMMENT ON COLUMN notification.notification_id IS '通知ID | 自增 | PK';
COMMENT ON COLUMN notification.biz_type IS '业务类型 | 投诉/验证任务/报告/措施 等';
COMMENT ON COLUMN notification.biz_id IS '业务ID | 业务主键';
COMMENT ON COLUMN notification.recipient_id IS '接收人 | 接收人 | FK';
COMMENT ON COLUMN notification.channel IS '渠道 | 邮件；飞书为二期（Q-09 已确认）';
COMMENT ON COLUMN notification.template_code IS '模板编码 | 消息模板';
COMMENT ON COLUMN notification.send_status IS '发送状态 | 待发送 / 成功 / 失败；失败可重试';
COMMENT ON COLUMN notification.sent_at IS '发送时间 | 发送时间';
COMMENT ON COLUMN notification.error_msg IS '失败原因 | 失败原因，支持重试';
COMMENT ON COLUMN notification.created_at IS '审计：创建时间';
COMMENT ON COLUMN notification.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN notification.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN notification.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN notification.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- interface_config   集成接口配置   [通知集成]
-- 来源：3.14
-- 集成接口定义，支持 API 配置、调试与监控。
-- ---------------------------------------------------------------------------
CREATE TABLE interface_config (
    interface_id             varchar(32) NOT NULL,
    interface_name           varchar(128) NOT NULL,
    source_system            varchar(16) NOT NULL,
    target_system            varchar(16),
    direction                varchar(16) NOT NULL,
    sync_mode                varchar(16),
    max_retry                integer,
    retry_interval           integer,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_interface_config PRIMARY KEY (interface_id)
);
COMMENT ON TABLE interface_config IS '集成接口配置 | 集成接口定义，支持 API 配置、调试与监控。';
COMMENT ON COLUMN interface_config.interface_id IS '接口ID | 系统生成 | PK';
COMMENT ON COLUMN interface_config.interface_name IS '接口名称 | 如 SAP 客户主数据同步';
COMMENT ON COLUMN interface_config.source_system IS '源系统 | SAP / PLM / MDM / MES / OA / BI / 邮箱';
COMMENT ON COLUMN interface_config.target_system IS '目标系统 | QMS 或外部系统';
COMMENT ON COLUMN interface_config.direction IS '数据流向 | 入向 / 出向 / 双向';
COMMENT ON COLUMN interface_config.sync_mode IS '同步方式 | 实时 / 定时 / 手动';
COMMENT ON COLUMN interface_config.max_retry IS '重试次数 | 异常数据自动重试次数，可配置';
COMMENT ON COLUMN interface_config.retry_interval IS '重试间隔(秒) | 重试间隔，可配置';
COMMENT ON COLUMN interface_config.is_active IS '是否启用 | 接口启停';
COMMENT ON COLUMN interface_config.created_at IS '审计：创建时间';
COMMENT ON COLUMN interface_config.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN interface_config.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN interface_config.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN interface_config.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- interface_log   接口调用日志   [通知集成]
-- 来源：3.14
-- 接口调用记录，支撑监控看板、异常报警、重试与手动补偿。
-- ---------------------------------------------------------------------------
CREATE TABLE interface_log (
    log_id                   bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    interface_id             varchar(32) NOT NULL,
    called_at                timestamptz NOT NULL,
    call_status              varchar(16) NOT NULL,
    request_body             text,
    response_body            text,
    error_msg                text,
    retry_count              integer,
    is_compensated           boolean,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_interface_log PRIMARY KEY (log_id)
);
COMMENT ON TABLE interface_log IS '接口调用日志 | 接口调用记录，支撑监控看板、异常报警、重试与手动补偿。';
COMMENT ON COLUMN interface_log.log_id IS '日志ID | 自增 | PK';
COMMENT ON COLUMN interface_log.interface_id IS '接口ID | 所属接口 | FK';
COMMENT ON COLUMN interface_log.called_at IS '调用时间 | 调用时间，用于监控看板';
COMMENT ON COLUMN interface_log.call_status IS '调用状态 | 成功 / 失败；异常时自动报警';
COMMENT ON COLUMN interface_log.request_body IS '请求报文 | 请求内容，用于调试';
COMMENT ON COLUMN interface_log.response_body IS '响应报文 | 响应内容';
COMMENT ON COLUMN interface_log.error_msg IS '失败原因 | 错误信息';
COMMENT ON COLUMN interface_log.retry_count IS '重试次数 | 已重试次数';
COMMENT ON COLUMN interface_log.is_compensated IS '是否已补偿 | 手动补偿标记，记录操作人';
COMMENT ON COLUMN interface_log.created_at IS '审计：创建时间';
COMMENT ON COLUMN interface_log.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN interface_log.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN interface_log.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN interface_log.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- knowledge_tag   知识标签   [知识报表]
-- 来源：3.11 / 1.5
-- 知识经验标签字典。标签独立存在，与知识条目的关联见 KnowledgeArticleTag，订阅见 Subscription。
-- ---------------------------------------------------------------------------
CREATE TABLE knowledge_tag (
    tag_id                   bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    tag_name                 varchar(64) NOT NULL,
    name_en                  varchar(64),
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_knowledge_tag PRIMARY KEY (tag_id),
    CONSTRAINT uq_knowledge_tag_name UNIQUE (tag_name)
);
COMMENT ON TABLE knowledge_tag IS '知识标签 | 知识经验标签字典。标签独立存在，与知识条目的关联见 KnowledgeArticleTag，订阅见 Subscription。';
COMMENT ON COLUMN knowledge_tag.tag_id IS '标签ID | 自增 | PK';
COMMENT ON COLUMN knowledge_tag.tag_name IS '标签名称(中) | 中文标签名，全局唯一';
COMMENT ON COLUMN knowledge_tag.name_en IS '标签名称(英) | 英文标签名，对应中英文切换（3.17）';
COMMENT ON COLUMN knowledge_tag.is_active IS '是否启用 | 停用后不再可选，已有历史关联保留';
COMMENT ON COLUMN knowledge_tag.created_at IS '审计：创建时间';
COMMENT ON COLUMN knowledge_tag.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN knowledge_tag.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN knowledge_tag.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN knowledge_tag.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- subscription   知识标签订阅   [知识报表]
-- 来源：3.11 / 1.5
-- 用户按标签订阅知识经验，标签下新增内容时收到提醒。
-- ---------------------------------------------------------------------------
CREATE TABLE subscription (
    subscription_id          bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    subscriber_id            varchar(32) NOT NULL,
    tag_id                   bigint NOT NULL,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_subscription PRIMARY KEY (subscription_id),
    CONSTRAINT uq_subscription UNIQUE (subscriber_id, tag_id)
);
COMMENT ON TABLE subscription IS '知识标签订阅 | 用户按标签订阅知识经验，标签下新增内容时收到提醒。';
COMMENT ON COLUMN subscription.subscription_id IS '订阅ID | 自增 | PK';
COMMENT ON COLUMN subscription.subscriber_id IS '订阅人 | 订阅人，人员主数据 | FK';
COMMENT ON COLUMN subscription.tag_id IS '标签ID | 订阅的标签 | FK';
COMMENT ON COLUMN subscription.is_active IS '是否启用 | 退订置为 false，保留历史记录';
COMMENT ON COLUMN subscription.created_at IS '审计：创建时间';
COMMENT ON COLUMN subscription.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN subscription.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN subscription.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN subscription.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- report_config   自定义报表配置   [知识报表]
-- 来源：3.10
-- 用户自定义报表字段、筛选条件的配置，可导出 PPT/PDF。
-- ---------------------------------------------------------------------------
CREATE TABLE report_config (
    config_id                bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    report_name              varchar(128) NOT NULL,
    report_type              varchar(32) NOT NULL,
    fields_json              jsonb,
    filters_json             jsonb,
    owner_id                 varchar(32),
    is_shared                boolean,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_report_config PRIMARY KEY (config_id)
);
COMMENT ON TABLE report_config IS '自定义报表配置 | 用户自定义报表字段、筛选条件的配置，可导出 PPT/PDF。';
COMMENT ON COLUMN report_config.config_id IS '配置ID | 自增 | PK';
COMMENT ON COLUMN report_config.report_name IS '报表名称 | 报表名称';
COMMENT ON COLUMN report_config.report_type IS '报表类型 | 8D报告状态统计 / Complaints(valid,#) / Complaint TPT / Customer incident / TPT分析 / 失效模式帕累托 / 客户维度 / Top5失效模式趋势';
COMMENT ON COLUMN report_config.fields_json IS '字段配置 | 用户自选的展示字段';
COMMENT ON COLUMN report_config.filters_json IS '筛选配置 | 时间范围、客户、产品类型等筛选条件';
COMMENT ON COLUMN report_config.owner_id IS '责任人 | KPI 责任方：BG Q / Sales Quality | FK';
COMMENT ON COLUMN report_config.is_shared IS '是否共享 | 配置是否可被他人复用';
COMMENT ON COLUMN report_config.created_at IS '审计：创建时间';
COMMENT ON COLUMN report_config.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN report_config.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN report_config.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN report_config.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- complaint   投诉单   [核心业务]
-- 来源：3.1.2
-- 客户投诉/内部质量问题的流程主表，8D 全流程的承载单据。
-- ---------------------------------------------------------------------------
CREATE TABLE complaint (
    complaint_id             varchar(16) NOT NULL,
    status_code              varchar(32) NOT NULL,
    complaint_type_code      varchar(32) NOT NULL,
    priority_code            varchar(16) NOT NULL,
    failure_location_code    varchar(32) NOT NULL,
    process_type             varchar(16) NOT NULL,
    created_by               varchar(32) NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    complaint_owner_id       varchar(32) NOT NULL,
    coordinator_id           varchar(32) NOT NULL,
    verification_owner_id    varchar(32),
    report_owner_id          varchar(32),
    start_date               date NOT NULL,
    target_date              date NOT NULL,
    customer_target_date     date NOT NULL,
    close_date               date,
    is_valid                 boolean,
    close_reason_code        varchar(32),
    customer_reference_id    varchar(64),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_complaint PRIMARY KEY (complaint_id),
    CONSTRAINT ck_complaint_dates CHECK (close_date IS NULL OR close_date >= start_date)
);
COMMENT ON TABLE complaint IS '投诉单 | 客户投诉/内部质量问题的流程主表，8D 全流程的承载单据。';
COMMENT ON COLUMN complaint.complaint_id IS '投诉ID | 规则 C+4 位年+5 位序号，如 C202600722；系统自动生成，不可修改（编号规则已确认 Q-13） | PK';
COMMENT ON COLUMN complaint.status_code IS '状态 | 系统按流程节点自动更新：登记-已启动 / 验证-已排期 等 | FK';
COMMENT ON COLUMN complaint.complaint_type_code IS '投诉类型 | 技术投诉(复杂/非复杂)、物流投诉、商务投诉、分析申请、内部投诉 | FK';
COMMENT ON COLUMN complaint.priority_code IS '优先级 | 标准 / 紧急 / 非常紧急；决定目标日期天数 | FK';
COMMENT ON COLUMN complaint.failure_location_code IS '失效位置 | 应用测试、产线拒收、可靠性监控等 | FK';
COMMENT ON COLUMN complaint.process_type IS '流程类型 | 8D / 4C（4C 为二期预留）';
COMMENT ON COLUMN complaint.created_by IS '发起人 | 自动填入当前登录用户，不可修改';
COMMENT ON COLUMN complaint.created_at IS '创建日期 | 自动填入当前时间，不可修改';
COMMENT ON COLUMN complaint.complaint_owner_id IS '投诉负责人 | 负责处理该投诉的主要责任人 | FK';
COMMENT ON COLUMN complaint.coordinator_id IS '协调人 | 负责协调流程推进的责任人；可修改目标日期 | FK';
COMMENT ON COLUMN complaint.verification_owner_id IS '验证负责人 | 负责样品验证的责任人 | FK';
COMMENT ON COLUMN complaint.report_owner_id IS '报告负责人 | 负责报告编制的责任人 | FK';
COMMENT ON COLUMN complaint.start_date IS '开始日期 | 默认 = 创建日期 + 7 天，允许修改';
COMMENT ON COLUMN complaint.target_date IS '目标日期 | 默认 = 开始日期 + 日历天数（非常紧急 7 / 紧急 10 / 标准 14），允许协调人修改';
COMMENT ON COLUMN complaint.customer_target_date IS '客户要求目标日期 | 客户要求的完成日期，手工录入；早于系统目标日期时预警';
COMMENT ON COLUMN complaint.close_date IS '关闭日期 | 投诉结案日期；仅在最终报告批准后可设置';
COMMENT ON COLUMN complaint.is_valid IS '是否有效 | 标识投诉是否有效；仅在验证阶段后可设置';
COMMENT ON COLUMN complaint.close_reason_code IS '结案原因 | 正常闭环 / 投诉不成立 / 转交根因组织';
COMMENT ON COLUMN complaint.customer_reference_id IS '客户参考ID | 客户侧的参考编号';
COMMENT ON COLUMN complaint.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN complaint.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN complaint.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- quality_partner   质量合作伙伴信息   [核心业务]
-- 来源：3.1.3
-- 投诉单对应的客户（质量合作伙伴）信息，与投诉单 1:1。
-- ---------------------------------------------------------------------------
CREATE TABLE quality_partner (
    complaint_id             varchar(16) NOT NULL,
    quality_partner_code     varchar(32) NOT NULL,
    application              varchar(4) NOT NULL,
    contact_person_id        varchar(32) NOT NULL,
    hs_code                  varchar(32),
    end_customer             varchar(128),
    eccn                     varchar(32),
    sub_segment_code         varchar(32) NOT NULL,
    ship_to_sold_to_code     varchar(32),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_quality_partner PRIMARY KEY (complaint_id)
);
COMMENT ON TABLE quality_partner IS '质量合作伙伴信息 | 投诉单对应的客户（质量合作伙伴）信息，与投诉单 1:1。';
COMMENT ON COLUMN quality_partner.complaint_id IS '投诉ID | 与投诉单共用主键 | PK,FK';
COMMENT ON COLUMN quality_partner.quality_partner_code IS '质量合作伙伴 | 关联客户主数据；不可手工新建 | FK';
COMMENT ON COLUMN quality_partner.application IS '应用 | Yes / No';
COMMENT ON COLUMN quality_partner.contact_person_id IS '联系人 | 主数据，可新增，与 Quality Partner 挂钩；8D 报告发送时自动带出为收件人 | FK';
COMMENT ON COLUMN quality_partner.hs_code IS 'HS 编码 | 海关商品编码';
COMMENT ON COLUMN quality_partner.end_customer IS '最终客户 | 终端客户名称';
COMMENT ON COLUMN quality_partner.eccn IS 'ECCN | 出口管制分类编码';
COMMENT ON COLUMN quality_partner.sub_segment_code IS '子分部 | 选择 Quality Partner 后自动带出，允许修改 | FK';
COMMENT ON COLUMN quality_partner.ship_to_sold_to_code IS '收货/售达方 | 来自 SAP 客户主数据，如通用武汉工厂、通用烟台工厂、深圳华为 | FK';
COMMENT ON COLUMN quality_partner.created_at IS '审计：创建时间';
COMMENT ON COLUMN quality_partner.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN quality_partner.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN quality_partner.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN quality_partner.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- failure_description   失效描述信息   [核心业务]
-- 来源：3.1.5
-- 客户反馈的失效现象与商务信息，与投诉单 1:1。
-- ---------------------------------------------------------------------------
CREATE TABLE failure_description (
    complaint_id             varchar(16) NOT NULL,
    customer_failure_description text,
    customer_failure_mode_code varchar(32) NOT NULL,
    d0_symptoms_description  text,
    comment                  text,
    quantity_failing         numeric(18,3),
    quantity_failing_uom     varchar(8),
    quality_returned         numeric(18,3),
    quality_returned_uom     varchar(8),
    customer_po              varchar(32),
    sales_order              varchar(32),
    supplier_invoice_number  varchar(32),
    shipped_directly         boolean,
    direct_communication     text,
    received_appr_pack       varchar(32),
    analysis_conclusion      text,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_failure_description PRIMARY KEY (complaint_id),
    CONSTRAINT ck_failure_desc_qty_failing CHECK (quantity_failing IS NULL OR quantity_failing >= 0),
    CONSTRAINT ck_failure_desc_qty_returned CHECK (quality_returned IS NULL OR quality_returned >= 0)
);
COMMENT ON TABLE failure_description IS '失效描述信息 | 客户反馈的失效现象与商务信息，与投诉单 1:1。';
COMMENT ON COLUMN failure_description.complaint_id IS '投诉ID | 与投诉单共用主键 | PK,FK';
COMMENT ON COLUMN failure_description.customer_failure_description IS '客户失效描述 | 富文本，支持附件与图片';
COMMENT ON COLUMN failure_description.customer_failure_mode_code IS '客户失效模式 | 主数据，必填 | FK';
COMMENT ON COLUMN failure_description.d0_symptoms_description IS 'D0 症状描述 | 支持上传 G8D Report 并 Record/Update 症状描述';
COMMENT ON COLUMN failure_description.comment IS '备注 | 自由文本';
COMMENT ON COLUMN failure_description.quantity_failing IS '失效数量 | 数量，须配单位';
COMMENT ON COLUMN failure_description.quantity_failing_uom IS '失效数量单位 | UoM';
COMMENT ON COLUMN failure_description.quality_returned IS '退回质量数量 | Quality returned 数量';
COMMENT ON COLUMN failure_description.quality_returned_uom IS '退回数量单位 | UoM';
COMMENT ON COLUMN failure_description.customer_po IS '客户采购订单 | Customer Purchase Order';
COMMENT ON COLUMN failure_description.sales_order IS '销售订单 | Sales Order';
COMMENT ON COLUMN failure_description.supplier_invoice_number IS '供应商发票号 | Supplier Invoice Number';
COMMENT ON COLUMN failure_description.shipped_directly IS '是否直发 | Shipped Directly';
COMMENT ON COLUMN failure_description.direct_communication IS '直接沟通 | Direct Communication 记录';
COMMENT ON COLUMN failure_description.received_appr_pack IS '收到认可包装 | Received Appr Pack';
COMMENT ON COLUMN failure_description.analysis_conclusion IS '投诉/分析结论 | 如：Pachage chipping was found on returned sample...';
COMMENT ON COLUMN failure_description.created_at IS '审计：创建时间';
COMMENT ON COLUMN failure_description.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN failure_description.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN failure_description.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN failure_description.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- sample   客诉样品   [核心业务]
-- 来源：3.1.6
-- 投诉单下的客诉样品，一个投诉可分多批多个样品。
-- ---------------------------------------------------------------------------
CREATE TABLE sample (
    sample_id                varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    customer_sample_id       varchar(64),
    champ_id                 varchar(32),
    sample_quantity          numeric(18,3),
    uom                      varchar(8),
    description              varchar(255),
    product_marking          varchar(128),
    application_area         varchar(64),
    reject_confirmed         boolean,
    conclusion               text,
    failure_type_l1_code     varchar(32),
    failure_type_l2_code     varchar(32),
    failure_type_l3_code     varchar(32),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_sample PRIMARY KEY (sample_id),
    CONSTRAINT ck_sample_qty CHECK (sample_quantity IS NULL OR sample_quantity >= 0)
);
COMMENT ON TABLE sample IS '客诉样品 | 投诉单下的客诉样品，一个投诉可分多批多个样品。';
COMMENT ON COLUMN sample.sample_id IS '样品ID | 系统生成 | PK';
COMMENT ON COLUMN sample.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN sample.customer_sample_id IS '客户样品ID | 客户侧样品编号';
COMMENT ON COLUMN sample.champ_id IS 'Champ ID | 由 Sales Quality 发送给客户，收到样品后登记';
COMMENT ON COLUMN sample.sample_quantity IS '样品数量 | 数量';
COMMENT ON COLUMN sample.uom IS '单位 | UoM';
COMMENT ON COLUMN sample.description IS '描述 | 样品描述';
COMMENT ON COLUMN sample.product_marking IS '产品标识 | Product Marking';
COMMENT ON COLUMN sample.application_area IS '应用领域 | Application Area';
COMMENT ON COLUMN sample.reject_confirmed IS '拒收确认 | Yes / No';
COMMENT ON COLUMN sample.conclusion IS '结论 | 样品级结论';
COMMENT ON COLUMN sample.failure_type_l1_code IS '失效类型L1 | 三级失效类型第一级 | FK';
COMMENT ON COLUMN sample.failure_type_l2_code IS '失效类型L2 | 须属于所选 L1 之下 | FK';
COMMENT ON COLUMN sample.failure_type_l3_code IS '失效类型L3 | 须属于所选 L2 之下 | FK';
COMMENT ON COLUMN sample.created_at IS '审计：创建时间';
COMMENT ON COLUMN sample.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN sample.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN sample.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN sample.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- shipment   物流快递   [核心业务]
-- 来源：3.2.1
-- 客诉不良品的寄送记录，一个投诉可有多批次。
-- ---------------------------------------------------------------------------
CREATE TABLE shipment (
    shipment_id              varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    sender_id                varchar(32) NOT NULL,
    receiver_id              varchar(32) NOT NULL,
    shipment_no              varchar(64),
    shipment_status          varchar(32),
    quantity_parts_shipped   numeric(18,3) NOT NULL,
    application              varchar(4),
    created_at               timestamptz NOT NULL DEFAULT now(),
    start_date               date,
    carrier_name             varchar(64) NOT NULL,
    carrier_tracking_number  varchar(64),
    target_date              date,
    close_date               date,
    comments                 text,
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_shipment PRIMARY KEY (shipment_id),
    CONSTRAINT ck_shipment_qty CHECK (quantity_parts_shipped >= 0)
);
COMMENT ON TABLE shipment IS '物流快递 | 客诉不良品的寄送记录，一个投诉可有多批次。';
COMMENT ON COLUMN shipment.shipment_id IS '物流ID | 系统生成 | PK';
COMMENT ON COLUMN shipment.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN shipment.sender_id IS '寄件人 | 必填 | FK';
COMMENT ON COLUMN shipment.receiver_id IS '收件人 | 人员主数据，必填 | FK';
COMMENT ON COLUMN shipment.shipment_no IS '物流单号 | Shipment ID';
COMMENT ON COLUMN shipment.shipment_status IS '物流状态 | 在途 / 已签收 / 已关闭 等';
COMMENT ON COLUMN shipment.quantity_parts_shipped IS '寄送数量 | Quantity of Parts Shipped，必填';
COMMENT ON COLUMN shipment.application IS '应用 | Yes / No';
COMMENT ON COLUMN shipment.created_at IS '创建日期 | 默认自动填写';
COMMENT ON COLUMN shipment.start_date IS '开始日期 | Start Date';
COMMENT ON COLUMN shipment.carrier_name IS '承运商 | Carrier Name，必填（流程图中 Speed carrier 角色）';
COMMENT ON COLUMN shipment.carrier_tracking_number IS '跟踪号 | Carrier Tracking Number';
COMMENT ON COLUMN shipment.target_date IS '目标日期 | 超过未关闭则标识超期';
COMMENT ON COLUMN shipment.close_date IS '关闭日期 | Close Date';
COMMENT ON COLUMN shipment.comments IS '备注 | Comments';
COMMENT ON COLUMN shipment.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN shipment.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN shipment.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN shipment.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- shipment_sample   物流样品关联   [核心业务]
-- 来源：3.2.2
-- 物流批次与样品的多对多关联（add/remove samples to the shipment）。
-- ---------------------------------------------------------------------------
CREATE TABLE shipment_sample (
    shipment_sample_id       bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    shipment_id              varchar(32) NOT NULL,
    sample_id                varchar(32) NOT NULL,
    description              varchar(255),
    date_code                varchar(32),
    db_id                    varchar(32),
    qty                      numeric(18,3),
    uom                      varchar(8),
    customer_sample_id       varchar(64),
    assembly_center          varchar(64),
    test_center              varchar(64),
    num_of_dies              integer,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_shipment_sample PRIMARY KEY (shipment_sample_id),
    CONSTRAINT uq_shipment_sample UNIQUE (shipment_id, sample_id),
    CONSTRAINT ck_shipment_sample_qty CHECK (qty IS NULL OR qty >= 0),
    CONSTRAINT ck_shipment_sample_dies CHECK (num_of_dies IS NULL OR num_of_dies >= 0)
);
COMMENT ON TABLE shipment_sample IS '物流样品关联 | 物流批次与样品的多对多关联（add/remove samples to the shipment）。';
COMMENT ON COLUMN shipment_sample.shipment_sample_id IS '关联ID | 自增 | PK';
COMMENT ON COLUMN shipment_sample.shipment_id IS '物流ID | 所属物流批次 | FK';
COMMENT ON COLUMN shipment_sample.sample_id IS '样品ID | 关联样品 | FK';
COMMENT ON COLUMN shipment_sample.description IS '描述 | 该批次下样品描述';
COMMENT ON COLUMN shipment_sample.date_code IS 'Date Code | 生产日期码';
COMMENT ON COLUMN shipment_sample.db_id IS 'DB ID | Die Bank 编号';
COMMENT ON COLUMN shipment_sample.qty IS '数量 | 该批次样品数量';
COMMENT ON COLUMN shipment_sample.uom IS '单位 | UoM';
COMMENT ON COLUMN shipment_sample.customer_sample_id IS '客户样品ID | Customer Sample ID';
COMMENT ON COLUMN shipment_sample.assembly_center IS '封装中心 | Assembly Center';
COMMENT ON COLUMN shipment_sample.test_center IS '测试中心 | Test Center';
COMMENT ON COLUMN shipment_sample.num_of_dies IS '芯片数 | #of Dies';
COMMENT ON COLUMN shipment_sample.created_at IS '审计：创建时间';
COMMENT ON COLUMN shipment_sample.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN shipment_sample.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN shipment_sample.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN shipment_sample.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- verification_task   验证任务   [核心业务]
-- 来源：3.3
-- D2 阶段的失效分析与验证任务，可自动或手动创建并排程。
-- ---------------------------------------------------------------------------
CREATE TABLE verification_task (
    task_id                  varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    sample_id                varchar(32),
    task_owner_id            varchar(32) NOT NULL,
    planned_start_date       date,
    target_completion_date   date NOT NULL,
    creation_mode            varchar(8) NOT NULL,
    task_status              varchar(32) NOT NULL,
    completed_at             timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_verification_task PRIMARY KEY (task_id)
);
COMMENT ON TABLE verification_task IS '验证任务 | D2 阶段的失效分析与验证任务，可自动或手动创建并排程。';
COMMENT ON COLUMN verification_task.task_id IS '任务ID | 系统生成 | PK';
COMMENT ON COLUMN verification_task.complaint_id IS '投诉ID | 必须关联到具体投诉 | FK';
COMMENT ON COLUMN verification_task.sample_id IS '样品ID | 一个投诉下对应多个样品的多个验证任务 | FK';
COMMENT ON COLUMN verification_task.task_owner_id IS '任务负责人 | 指定任务负责人 | FK';
COMMENT ON COLUMN verification_task.planned_start_date IS '计划开始日期 | 任务排程';
COMMENT ON COLUMN verification_task.target_completion_date IS '目标完成日期 | 与投诉目标日期冲突时提示';
COMMENT ON COLUMN verification_task.creation_mode IS '创建方式 | 自动 / 手动';
COMMENT ON COLUMN verification_task.task_status IS '任务状态 | 待排期 / 进行中 / 已完成';
COMMENT ON COLUMN verification_task.completed_at IS '完成日期 | 实际完成时间';
COMMENT ON COLUMN verification_task.created_at IS '审计：创建时间';
COMMENT ON COLUMN verification_task.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN verification_task.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN verification_task.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN verification_task.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- verification_result   验证结果   [核心业务]
-- 来源：3.3
-- 验证任务的测试结果明细，支持逐个录入与批量汇总录入。
-- ---------------------------------------------------------------------------
CREATE TABLE verification_result (
    result_id                bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    task_id                  varchar(32) NOT NULL,
    test_item                varchar(64),
    failure_type_l1_code     varchar(32),
    failure_type_l2_code     varchar(32),
    failure_type_l3_code     varchar(32),
    result_conclusion        text,
    entry_mode               varchar(8),
    recorded_by              varchar(32) NOT NULL,
    recorded_at              timestamptz NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_verification_result PRIMARY KEY (result_id)
);
COMMENT ON TABLE verification_result IS '验证结果 | 验证任务的测试结果明细，支持逐个录入与批量汇总录入。';
COMMENT ON COLUMN verification_result.result_id IS '结果ID | 自增 | PK';
COMMENT ON COLUMN verification_result.task_id IS '任务ID | 所属验证任务 | FK';
COMMENT ON COLUMN verification_result.test_item IS '测试项 | 如 X-Ray、电性测试等';
COMMENT ON COLUMN verification_result.failure_type_l1_code IS '失效类型L1 | 三级级联 | FK';
COMMENT ON COLUMN verification_result.failure_type_l2_code IS '失效类型L2 | 三级级联 | FK';
COMMENT ON COLUMN verification_result.failure_type_l3_code IS '失效类型L3 | 三级级联 | FK';
COMMENT ON COLUMN verification_result.result_conclusion IS '结果结论 | 该测试项结论';
COMMENT ON COLUMN verification_result.entry_mode IS '录入方式 | 逐个 / 批量';
COMMENT ON COLUMN verification_result.recorded_by IS '录入人 | 记录录入人 | FK';
COMMENT ON COLUMN verification_result.recorded_at IS '录入时间 | 记录录入时间';
COMMENT ON COLUMN verification_result.created_at IS '审计：创建时间';
COMMENT ON COLUMN verification_result.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN verification_result.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN verification_result.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN verification_result.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- attachment   附件   [核心业务]
-- 来源：3.1.5 / 3.3 / 3.7
-- 全系统统一附件表。通过 biz_type + biz_id 多态关联任意单据（投诉/样品/物流/验证任务/根因/措施/报告），无物理外键；图中仅示意与投诉单的关联，其余关联见「关系清单」。
-- ---------------------------------------------------------------------------
CREATE TABLE attachment (
    attachment_id            bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    biz_type                 varchar(32) NOT NULL,
    biz_id                   varchar(32) NOT NULL,
    file_name                varchar(255) NOT NULL,
    file_size                bigint NOT NULL,
    file_type                varchar(32) NOT NULL,
    storage_path             varchar(512) NOT NULL,
    uploaded_by              varchar(32) NOT NULL,
    uploaded_at              timestamptz NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_attachment PRIMARY KEY (attachment_id),
    CONSTRAINT ck_attachment_biz_type CHECK (biz_type <> '')
);
COMMENT ON TABLE attachment IS '附件 | 全系统统一附件表。通过 biz_type + biz_id 多态关联任意单据（投诉/样品/物流/验证任务/根因/措施/报告），无物理外键；图中仅示意与投诉单的关联，其余关联见「关系清单」。';
COMMENT ON COLUMN attachment.attachment_id IS '附件ID | 自增 | PK';
COMMENT ON COLUMN attachment.biz_type IS '业务类型 | 投诉/样品/物流/验证任务/根因/措施/报告 等';
COMMENT ON COLUMN attachment.biz_id IS '业务ID | 对应业务主键（多态外键）';
COMMENT ON COLUMN attachment.file_name IS '文件名 | 原始文件名';
COMMENT ON COLUMN attachment.file_size IS '文件大小 | 字节；单文件上限 50MB，白名单 jpg/png/pdf/docx/xlsx/zip/mp4，上传即杀毒（Q-15 已确认）';
COMMENT ON COLUMN attachment.file_type IS '文件类型 | 扩展名/ MIME';
COMMENT ON COLUMN attachment.storage_path IS '存储路径 | 对象存储或文件服务路径';
COMMENT ON COLUMN attachment.uploaded_by IS '上传人 | 记录上传人 | FK';
COMMENT ON COLUMN attachment.uploaded_at IS '上传时间 | 记录上传时间';
COMMENT ON COLUMN attachment.created_at IS '审计：创建时间';
COMMENT ON COLUMN attachment.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN attachment.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN attachment.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN attachment.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- containment_action   遏制措施   [核心业务]
-- 来源：3.4
-- D3 阶段遏制措施，在验证问题成立后登记并跟踪。
-- ---------------------------------------------------------------------------
CREATE TABLE containment_action (
    action_id                varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    nex_sample_number        varchar(64),
    customer_sample_number   varchar(64),
    planned_action           text NOT NULL,
    owner_id                 varchar(32) NOT NULL,
    completed_date           date,
    status_code              varchar(32) NOT NULL,
    result                   text,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_containment_action PRIMARY KEY (action_id)
);
COMMENT ON TABLE containment_action IS '遏制措施 | D3 阶段遏制措施，在验证问题成立后登记并跟踪。';
COMMENT ON COLUMN containment_action.action_id IS '措施ID | 系统生成 | PK';
COMMENT ON COLUMN containment_action.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN containment_action.nex_sample_number IS 'NEX样品号 | NEX sample number';
COMMENT ON COLUMN containment_action.customer_sample_number IS '客户样品号 | customer sample number';
COMMENT ON COLUMN containment_action.planned_action IS '计划措施 | planned action';
COMMENT ON COLUMN containment_action.owner_id IS '责任人 | owner，人员主数据 | FK';
COMMENT ON COLUMN containment_action.completed_date IS '完成日期 | completed date；早于计划日期时提示异常';
COMMENT ON COLUMN containment_action.status_code IS '状态 | Status | FK';
COMMENT ON COLUMN containment_action.result IS '结果 | result 实施结果';
COMMENT ON COLUMN containment_action.created_at IS '审计：创建时间';
COMMENT ON COLUMN containment_action.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN containment_action.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN containment_action.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN containment_action.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- root_cause   根因分析   [核心业务]
-- 来源：3.5
-- D4 阶段根因分析条目，验证结束后创建，一个投诉可多条。
-- ---------------------------------------------------------------------------
CREATE TABLE root_cause (
    root_cause_id            varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    root_cause_desc          text NOT NULL,
    root_cause_summary       varchar(500),
    risk_assessment          text,
    responsible_org_type     varchar(16),
    responsible_org_code     varchar(32),
    transferred_to_id        varchar(32),
    transferred_at           timestamptz,
    status_code              varchar(32) NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_root_cause PRIMARY KEY (root_cause_id)
);
COMMENT ON TABLE root_cause IS '根因分析 | D4 阶段根因分析条目，验证结束后创建，一个投诉可多条。';
COMMENT ON COLUMN root_cause.root_cause_id IS '根因ID | 序列号，系统自动生成，不可修改 | PK';
COMMENT ON COLUMN root_cause.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN root_cause.root_cause_desc IS '根因描述 | 富文本，支持图片';
COMMENT ON COLUMN root_cause.root_cause_summary IS '根因摘要 | 用于报表与知识检索';
COMMENT ON COLUMN root_cause.risk_assessment IS '风险评估 | 风险评估内容';
COMMENT ON COLUMN root_cause.responsible_org_type IS '根因归属 | 内部 / 外部根因组织；对应流程图 Root cause within Nexperia? 分支';
COMMENT ON COLUMN root_cause.responsible_org_code IS '责任组织 | 根因归属的组织 | FK';
COMMENT ON COLUMN root_cause.transferred_to_id IS '转交对象 | 转交根因组织时的接收人 | FK';
COMMENT ON COLUMN root_cause.transferred_at IS '转交时间 | 转交留痕';
COMMENT ON COLUMN root_cause.status_code IS '状态 | 待分析 / 分析中 / 已确认 | FK';
COMMENT ON COLUMN root_cause.created_at IS '审计：创建时间';
COMMENT ON COLUMN root_cause.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN root_cause.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN root_cause.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN root_cause.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- why_analysis   3x5Why与鱼骨图   [核心业务]
-- 来源：3.5
-- 根因分析工具内容，支持上传关联与系统内在线编辑，含 AI 生成与质量反馈。
-- ---------------------------------------------------------------------------
CREATE TABLE why_analysis (
    analysis_id              bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    root_cause_id            varchar(32) NOT NULL,
    analysis_type            varchar(16) NOT NULL,
    content_json             jsonb,
    is_ai_generated          boolean,
    ai_quality_feedback      varchar(32),
    version_no               integer NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_why_analysis PRIMARY KEY (analysis_id)
);
COMMENT ON TABLE why_analysis IS '3x5Why与鱼骨图 | 根因分析工具内容，支持上传关联与系统内在线编辑，含 AI 生成与质量反馈。';
COMMENT ON COLUMN why_analysis.analysis_id IS '分析ID | 自增 | PK';
COMMENT ON COLUMN why_analysis.root_cause_id IS '根因ID | 所属根因条目 | FK';
COMMENT ON COLUMN why_analysis.analysis_type IS '分析类型 | 3x5Why / 鱼骨图';
COMMENT ON COLUMN why_analysis.content_json IS '内容 | 在线编辑的结构化内容（3 条路径 x 5 层 Why / 鱼骨图分支）';
COMMENT ON COLUMN why_analysis.is_ai_generated IS '是否AI生成 | AI 生成初稿的标记；一期恒为 false，AI 生成能力属二期（Q-03 已确认）';
COMMENT ON COLUMN why_analysis.ai_quality_feedback IS 'AI生成质量反馈 | 用户对 AI 生成质量的反馈，可统计';
COMMENT ON COLUMN why_analysis.version_no IS '版本号 | 在线编辑保存留版本历史';
COMMENT ON COLUMN why_analysis.created_at IS '审计：创建时间';
COMMENT ON COLUMN why_analysis.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN why_analysis.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN why_analysis.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN why_analysis.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- corrective_action   纠正措施   [核心业务]
-- 来源：3.6
-- D5 阶段永久纠正措施，基于根因制定并分配。
-- ---------------------------------------------------------------------------
CREATE TABLE corrective_action (
    corrective_action_id     varchar(32) NOT NULL,
    root_cause_id            varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    nex_sample_number        varchar(64),
    customer_sample_id       varchar(64),
    planned_action_desc      text NOT NULL,
    owner_id                 varchar(32) NOT NULL,
    target_date              date NOT NULL,
    status_code              varchar(32) NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_corrective_action PRIMARY KEY (corrective_action_id)
);
COMMENT ON TABLE corrective_action IS '纠正措施 | D5 阶段永久纠正措施，基于根因制定并分配。';
COMMENT ON COLUMN corrective_action.corrective_action_id IS '措施ID | 系统生成 | PK';
COMMENT ON COLUMN corrective_action.root_cause_id IS '根因ID | 基于根因制定 | FK';
COMMENT ON COLUMN corrective_action.complaint_id IS '投诉ID | 冗余外键，便于按投诉汇总 | FK';
COMMENT ON COLUMN corrective_action.nex_sample_number IS 'NEX样品号 | Nexperia Sample Number';
COMMENT ON COLUMN corrective_action.customer_sample_id IS '客户样品ID | Customer Sample ID';
COMMENT ON COLUMN corrective_action.planned_action_desc IS '计划措施描述 | Planned actions description';
COMMENT ON COLUMN corrective_action.owner_id IS '责任人 | Owner | FK';
COMMENT ON COLUMN corrective_action.target_date IS '目标日期 | Target date，必填';
COMMENT ON COLUMN corrective_action.status_code IS '状态 | Status | FK';
COMMENT ON COLUMN corrective_action.created_at IS '审计：创建时间';
COMMENT ON COLUMN corrective_action.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN corrective_action.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN corrective_action.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN corrective_action.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- action_verification   措施实施与验证   [核心业务]
-- 来源：3.7
-- D6 阶段纠正措施的实施反馈与有效性验证。
-- ---------------------------------------------------------------------------
CREATE TABLE action_verification (
    verification_id          bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    corrective_action_id     varchar(32) NOT NULL,
    actual_completion_date   date,
    verification_result      text,
    is_effective             boolean,
    verified_by              varchar(32),
    verified_at              timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_action_verification PRIMARY KEY (verification_id)
);
COMMENT ON TABLE action_verification IS '措施实施与验证 | D6 阶段纠正措施的实施反馈与有效性验证。';
COMMENT ON COLUMN action_verification.verification_id IS '验证ID | 自增 | PK';
COMMENT ON COLUMN action_verification.corrective_action_id IS '措施ID | 所属纠正措施 | FK';
COMMENT ON COLUMN action_verification.actual_completion_date IS '实际完成日期 | 负责人填写实际完成日期';
COMMENT ON COLUMN action_verification.verification_result IS '验证结果 | 验证结果及结论';
COMMENT ON COLUMN action_verification.is_effective IS '是否有效 | 不通过时置待返工并通知负责人';
COMMENT ON COLUMN action_verification.verified_by IS '验证人 | 验证人 | FK';
COMMENT ON COLUMN action_verification.verified_at IS '验证时间 | 验证时间';
COMMENT ON COLUMN action_verification.created_at IS '审计：创建时间';
COMMENT ON COLUMN action_verification.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN action_verification.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN action_verification.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN action_verification.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- prevention_file_update   预防再发生文件更新   [核心业务]
-- 来源：3.8
-- D7 阶段需更新的文件清单与状态跟踪。
-- ---------------------------------------------------------------------------
CREATE TABLE prevention_file_update (
    update_id                bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    nex_sample_number        varchar(64),
    customer_sample_id       varchar(64),
    file_type_code           varchar(32) NOT NULL,
    control_program          varchar(128),
    reference_number         varchar(64),
    status_code              varchar(32) NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_prevention_file_update PRIMARY KEY (update_id)
);
COMMENT ON TABLE prevention_file_update IS '预防再发生文件更新 | D7 阶段需更新的文件清单与状态跟踪。';
COMMENT ON COLUMN prevention_file_update.update_id IS '记录ID | 自增 | PK';
COMMENT ON COLUMN prevention_file_update.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN prevention_file_update.nex_sample_number IS 'NEX样品号 | Nexperia Sample Number';
COMMENT ON COLUMN prevention_file_update.customer_sample_id IS '客户样品ID | Customer Sample ID';
COMMENT ON COLUMN prevention_file_update.file_type_code IS '文件类型 | FMEA / Control Plan / OCAP / SOP / Update on Flow | FK';
COMMENT ON COLUMN prevention_file_update.control_program IS '控制计划 | Control program';
COMMENT ON COLUMN prevention_file_update.reference_number IS '参考编号 | reference number';
COMMENT ON COLUMN prevention_file_update.status_code IS '状态 | status；全部完成后方可进入 D8 | FK';
COMMENT ON COLUMN prevention_file_update.created_at IS '审计：创建时间';
COMMENT ON COLUMN prevention_file_update.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN prevention_file_update.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN prevention_file_update.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN prevention_file_update.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- report_8d   8D报告   [核心业务]
-- 来源：3.9
-- D8 阶段 8D 报告，按 D1-D7 内容自动生成，区分中期与终期。
-- ---------------------------------------------------------------------------
CREATE TABLE report_8d (
    report_id                varchar(32) NOT NULL,
    complaint_id             varchar(16) NOT NULL,
    report_type              varchar(8) NOT NULL,
    version_no               varchar(16) NOT NULL,
    current_step             varchar(4),
    report_start_date        date,
    report_target_date       date,
    report_close_date        date,
    approval_status          varchar(16) NOT NULL,
    generated_at             timestamptz,
    template_code            varchar(32),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_report_8d PRIMARY KEY (report_id),
    CONSTRAINT ck_report8d_dates CHECK (report_close_date IS NULL OR report_start_date IS NOT NULL),
    CONSTRAINT ck_report8d_target CHECK (report_target_date IS NULL OR report_start_date IS NULL OR report_target_date >= report_start_date)
);
COMMENT ON TABLE report_8d IS '8D报告 | D8 阶段 8D 报告，按 D1-D7 内容自动生成，区分中期与终期。';
COMMENT ON COLUMN report_8d.report_id IS '报告ID | 系统生成 | PK';
COMMENT ON COLUMN report_8d.complaint_id IS '投诉ID | 所属投诉 | FK';
COMMENT ON COLUMN report_8d.report_type IS '报告类型 | 中期 / 终期；中间过程与最终阶段均可导出';
COMMENT ON COLUMN report_8d.version_no IS '版本号 | 报告版本，文件命名含版本';
COMMENT ON COLUMN report_8d.current_step IS '当前步骤 | D1-D8，标识报告编制进度';
COMMENT ON COLUMN report_8d.report_start_date IS '开始日期 | = 报告发送给客户的日期，自动填充且不可修改';
COMMENT ON COLUMN report_8d.report_target_date IS '目标日期 | 默认 = 开始日期 + 14 天，可修改';
COMMENT ON COLUMN report_8d.report_close_date IS '关闭日期 | = 报告发送日（同开始日期），自动填充';
COMMENT ON COLUMN report_8d.approval_status IS '审批状态 | 草稿 / 审批中 / 已批准 / 已驳回';
COMMENT ON COLUMN report_8d.generated_at IS '生成时间 | 报告生成时间';
COMMENT ON COLUMN report_8d.template_code IS '模板编号 | 按安世格式定制的模板；一期以 XTE-0071 8D Problem Report.docx 为准（Q-10 已确认）';
COMMENT ON COLUMN report_8d.created_at IS '审计：创建时间';
COMMENT ON COLUMN report_8d.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN report_8d.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN report_8d.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN report_8d.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- report_step_owner   报告步骤责任人   [核心业务]
-- 来源：3.9 / 1.5
-- 8D 报告各步骤的 owner 分配与完成状态。
-- ---------------------------------------------------------------------------
CREATE TABLE report_step_owner (
    step_owner_id            bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    report_id                varchar(32) NOT NULL,
    step_code                varchar(4) NOT NULL,
    owner_id                 varchar(32) NOT NULL,
    status_code              varchar(32) NOT NULL,
    completed_at             timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_report_step_owner PRIMARY KEY (step_owner_id),
    CONSTRAINT uq_report_step_owner UNIQUE (report_id, step_code)
);
COMMENT ON TABLE report_step_owner IS '报告步骤责任人 | 8D 报告各步骤的 owner 分配与完成状态。';
COMMENT ON COLUMN report_step_owner.step_owner_id IS '记录ID | 自增 | PK';
COMMENT ON COLUMN report_step_owner.report_id IS '报告ID | 所属报告 | FK';
COMMENT ON COLUMN report_step_owner.step_code IS '步骤代码 | D1-D8';
COMMENT ON COLUMN report_step_owner.owner_id IS '责任人 | 分配后通过邮件通知到人 | FK';
COMMENT ON COLUMN report_step_owner.status_code IS '状态 | 待处理 / 编写中 / 已完成 | FK';
COMMENT ON COLUMN report_step_owner.completed_at IS '完成时间 | 该步骤完成时间';
COMMENT ON COLUMN report_step_owner.created_at IS '审计：创建时间';
COMMENT ON COLUMN report_step_owner.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN report_step_owner.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN report_step_owner.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN report_step_owner.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- report_distribution   报告发送与沟通日志   [核心业务]
-- 来源：3.9
-- 报告发送记录与沟通日志，发送后自动生成且不可修改。
-- ---------------------------------------------------------------------------
CREATE TABLE report_distribution (
    log_id                   bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    report_id                varchar(32) NOT NULL,
    sender_id                varchar(32) NOT NULL,
    recipient                varchar(255) NOT NULL,
    cc_list                  varchar(1000),
    sent_at                  timestamptz NOT NULL,
    attachment_version       varchar(16),
    channel                  varchar(16),
    distribution_list        varchar(1000),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_report_distribution PRIMARY KEY (log_id)
);
COMMENT ON TABLE report_distribution IS '报告发送与沟通日志 | 报告发送记录与沟通日志，发送后自动生成且不可修改。';
COMMENT ON COLUMN report_distribution.log_id IS '日志ID | 自增 | PK';
COMMENT ON COLUMN report_distribution.report_id IS '报告ID | 所属报告 | FK';
COMMENT ON COLUMN report_distribution.sender_id IS '发件人 | 自动为当前 Sales Quality 用户 | FK';
COMMENT ON COLUMN report_distribution.recipient IS '收件人 | 自动带出客户联系人邮箱，可手工调整';
COMMENT ON COLUMN report_distribution.cc_list IS '抄送 | 支持多个抄送人';
COMMENT ON COLUMN report_distribution.sent_at IS '发送时间 | 发送时间，写入沟通日志';
COMMENT ON COLUMN report_distribution.attachment_version IS '附件版本 | 本次发送的报告版本';
COMMENT ON COLUMN report_distribution.channel IS '发送渠道 | 邮件 / 其他';
COMMENT ON COLUMN report_distribution.distribution_list IS '分发列表 | Distribution List；样例报告含 Reported by / Approved by / Distribution List 签署区';
COMMENT ON COLUMN report_distribution.created_at IS '审计：创建时间';
COMMENT ON COLUMN report_distribution.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN report_distribution.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN report_distribution.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN report_distribution.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- approval_task   审批任务   [核心业务]
-- 来源：3.9 / 3.14.1
-- 统一审批任务，走 OA 审批流并回写状态。
-- ---------------------------------------------------------------------------
CREATE TABLE approval_task (
    approval_id              varchar(32) NOT NULL,
    biz_type                 varchar(32) NOT NULL,
    biz_id                   varchar(32) NOT NULL,
    approver_id              varchar(32) NOT NULL,
    oa_instance_id           varchar(64),
    status_code              varchar(32) NOT NULL,
    approval_comment         text,
    pushed_at                timestamptz,
    completed_at             timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_approval_task PRIMARY KEY (approval_id)
);
COMMENT ON TABLE approval_task IS '审批任务 | 统一审批任务，走 OA 审批流并回写状态。';
COMMENT ON COLUMN approval_task.approval_id IS '审批ID | 系统生成 | PK';
COMMENT ON COLUMN approval_task.biz_type IS '业务类型 | 报告/措施 等';
COMMENT ON COLUMN approval_task.biz_id IS '业务ID | 对应业务主键';
COMMENT ON COLUMN approval_task.approver_id IS '审批人 | 按流程配置的审批人 | FK';
COMMENT ON COLUMN approval_task.oa_instance_id IS 'OA实例号 | OA 侧流程实例号，用于状态回写';
COMMENT ON COLUMN approval_task.status_code IS '状态 | 待审批 / 已批准 / 已驳回 | FK';
COMMENT ON COLUMN approval_task.approval_comment IS '审批意见 | 驳回时退回报告负责人并通知';
COMMENT ON COLUMN approval_task.pushed_at IS '推送时间 | 推送至 OA 的时间';
COMMENT ON COLUMN approval_task.completed_at IS '完成时间 | 审批完成时间；一期仅 PC 端，移动端审批属二期（Q-09 已确认）';
COMMENT ON COLUMN approval_task.created_at IS '审计：创建时间';
COMMENT ON COLUMN approval_task.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN approval_task.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN approval_task.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN approval_task.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- product_master   产品主数据   [主数据]
-- 来源：3.14.2 (PLM/SAP)
-- 来自 PLM/SAP 的 12NC/9NC 物料主数据。
-- ---------------------------------------------------------------------------
CREATE TABLE product_master (
    material_code            varchar(32) NOT NULL,
    description              varchar(255),
    product_type_code        varchar(32),
    business_group           varchar(32),
    business_unit            varchar(32),
    packing_type_code        varchar(32),
    synced_at                timestamptz,
    is_active                boolean NOT NULL DEFAULT true,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_product_master PRIMARY KEY (material_code)
);
COMMENT ON TABLE product_master IS '产品主数据 | 来自 PLM/SAP 的 12NC/9NC 物料主数据。';
COMMENT ON COLUMN product_master.material_code IS '物料编码 | 12NC / 9NC，保持源系统编码 | PK';
COMMENT ON COLUMN product_master.description IS '产品描述 | 同步自 PLM/SAP';
COMMENT ON COLUMN product_master.product_type_code IS '产品类型 | 产品分类 | FK';
COMMENT ON COLUMN product_master.business_group IS '事业部 | Business Group';
COMMENT ON COLUMN product_master.business_unit IS '业务单元 | Business Unit';
COMMENT ON COLUMN product_master.packing_type_code IS '包装类型 | Packing Type | FK';
COMMENT ON COLUMN product_master.synced_at IS '同步时间 | 同步时间';
COMMENT ON COLUMN product_master.is_active IS '是否启用 | 停用不删除';
COMMENT ON COLUMN product_master.created_at IS '审计：创建时间';
COMMENT ON COLUMN product_master.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN product_master.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN product_master.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN product_master.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- knowledge_article   知识条目   [知识报表]
-- 来源：3.11
-- 知识中心的流程文件、模板、手册与问题解决经验条目。
-- ---------------------------------------------------------------------------
CREATE TABLE knowledge_article (
    article_id               bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    title                    varchar(255) NOT NULL,
    category                 varchar(32) NOT NULL,
    content                  text,
    source_complaint_id      varchar(16),
    status_code              varchar(32),
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_knowledge_article PRIMARY KEY (article_id)
);
COMMENT ON TABLE knowledge_article IS '知识条目 | 知识中心的流程文件、模板、手册与问题解决经验条目。';
COMMENT ON COLUMN knowledge_article.article_id IS '知识ID | 自增 | PK';
COMMENT ON COLUMN knowledge_article.title IS '标题 | 标题';
COMMENT ON COLUMN knowledge_article.category IS '分类 | 流程文件 / 5Why分析模板 / 操作手册 / 8D培训教材 / 问题解决经验';
COMMENT ON COLUMN knowledge_article.content IS '内容 | 正文内容；文件类走附件';
COMMENT ON COLUMN knowledge_article.source_complaint_id IS '来源投诉ID | 结案后沉淀的经验来源 | FK';
COMMENT ON COLUMN knowledge_article.status_code IS '状态 | 草稿 / 已发布 | FK';
COMMENT ON COLUMN knowledge_article.created_at IS '审计：创建时间';
COMMENT ON COLUMN knowledge_article.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN knowledge_article.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN knowledge_article.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN knowledge_article.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- knowledge_article_tag   知识条目标签关联   [知识报表]
-- 来源：3.11 / 1.5
-- 知识条目与标签的多对多关联。一个知识条目可打多个标签，一个标签可归集多个条目。
-- ---------------------------------------------------------------------------
CREATE TABLE knowledge_article_tag (
    article_tag_id           bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    article_id               bigint NOT NULL,
    tag_id                   bigint NOT NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_knowledge_article_tag PRIMARY KEY (article_tag_id),
    CONSTRAINT uq_knowledge_article_tag UNIQUE (article_id, tag_id)
);
COMMENT ON TABLE knowledge_article_tag IS '知识条目标签关联 | 知识条目与标签的多对多关联。一个知识条目可打多个标签，一个标签可归集多个条目。';
COMMENT ON COLUMN knowledge_article_tag.article_tag_id IS '关联ID | 自增 | PK';
COMMENT ON COLUMN knowledge_article_tag.article_id IS '知识ID | 所属知识条目 | FK';
COMMENT ON COLUMN knowledge_article_tag.tag_id IS '标签ID | 关联标签 | FK';
COMMENT ON COLUMN knowledge_article_tag.created_at IS '审计：创建时间';
COMMENT ON COLUMN knowledge_article_tag.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN knowledge_article_tag.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN knowledge_article_tag.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN knowledge_article_tag.is_deleted IS '审计：软删除标记';

-- ---------------------------------------------------------------------------
-- product_info   产品信息   [核心业务]
-- 来源：3.1.4
-- 投诉涉及的产品信息，与投诉单 1:1。
-- ---------------------------------------------------------------------------
CREATE TABLE product_info (
    complaint_id             varchar(16) NOT NULL,
    material_code            varchar(32),
    product_type_code        varchar(32) NOT NULL,
    packing_type_code        varchar(32) NOT NULL,
    business_group           varchar(32),
    business_unit            varchar(32),
    nc9                      varchar(32),
    mag                      varchar(32),
    customer_part_no         varchar(64),
    tg4                      varchar(32),
    tg5                      varchar(32),
    tg6                      varchar(32),
    product_status           varchar(32),
    is_protected             boolean,
    created_at               timestamptz NOT NULL DEFAULT now(),
    created_by               varchar(32),
    updated_at               timestamptz NOT NULL DEFAULT now(),
    updated_by               varchar(32),
    is_deleted               boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_product_info PRIMARY KEY (complaint_id)
);
COMMENT ON TABLE product_info IS '产品信息 | 投诉涉及的产品信息，与投诉单 1:1。';
COMMENT ON COLUMN product_info.complaint_id IS '投诉ID | 与投诉单共用主键 | PK,FK';
COMMENT ON COLUMN product_info.material_code IS '物料编码 | 12NC / 9NC，关联产品主数据 | FK';
COMMENT ON COLUMN product_info.product_type_code IS '产品类型 | 必填 | FK';
COMMENT ON COLUMN product_info.packing_type_code IS '包装类型 | 必填 | FK';
COMMENT ON COLUMN product_info.business_group IS '事业部 | Business Group';
COMMENT ON COLUMN product_info.business_unit IS '业务单元 | Business Unit';
COMMENT ON COLUMN product_info.nc9 IS '9NC | 9 位物料编码';
COMMENT ON COLUMN product_info.mag IS 'MAG | 文档原文字段，含义待业务方确认';
COMMENT ON COLUMN product_info.customer_part_no IS '客户料号 | 客户方物料编号';
COMMENT ON COLUMN product_info.tg4 IS '4TG | 文档原文字段，含义待业务方确认';
COMMENT ON COLUMN product_info.tg5 IS '5GT | 文档原文字段，含义待业务方确认';
COMMENT ON COLUMN product_info.tg6 IS '6GT | 文档原文字段，含义待业务方确认';
COMMENT ON COLUMN product_info.product_status IS '产品状态 | 产品生命周期状态';
COMMENT ON COLUMN product_info.is_protected IS '受保护 | Protected 标记';
COMMENT ON COLUMN product_info.created_at IS '审计：创建时间';
COMMENT ON COLUMN product_info.created_by IS '审计：创建人（员工ID）';
COMMENT ON COLUMN product_info.updated_at IS '审计：最后修改时间';
COMMENT ON COLUMN product_info.updated_by IS '审计：最后修改人（员工ID）';
COMMENT ON COLUMN product_info.is_deleted IS '审计：软删除标记';

-- ===========================================================================
-- 外键约束（全部建表后统一添加）
-- ===========================================================================
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_complaint_type_code FOREIGN KEY (complaint_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_priority_code FOREIGN KEY (priority_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_failure_location_code FOREIGN KEY (failure_location_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_complaint_owner_id FOREIGN KEY (complaint_owner_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_coordinator_id FOREIGN KEY (coordinator_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_verification_owner_id FOREIGN KEY (verification_owner_id) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE complaint ADD CONSTRAINT fk_complaint_report_owner_id FOREIGN KEY (report_owner_id) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE quality_partner ADD CONSTRAINT fk_quality_partner_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE quality_partner ADD CONSTRAINT fk_quality_partner_quality_partner_code FOREIGN KEY (quality_partner_code) REFERENCES customer (customer_code) ON DELETE RESTRICT;
ALTER TABLE quality_partner ADD CONSTRAINT fk_quality_partner_contact_person_id FOREIGN KEY (contact_person_id) REFERENCES contact_person (contact_id) ON DELETE RESTRICT;
ALTER TABLE quality_partner ADD CONSTRAINT fk_quality_partner_sub_segment_code FOREIGN KEY (sub_segment_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE quality_partner ADD CONSTRAINT fk_quality_partner_ship_to_sold_to_code FOREIGN KEY (ship_to_sold_to_code) REFERENCES ship_to_sold_to (ship_to_code) ON DELETE RESTRICT;
ALTER TABLE product_info ADD CONSTRAINT fk_product_info_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE product_info ADD CONSTRAINT fk_product_info_material_code FOREIGN KEY (material_code) REFERENCES product_master (material_code) ON DELETE RESTRICT;
ALTER TABLE product_info ADD CONSTRAINT fk_product_info_product_type_code FOREIGN KEY (product_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE product_info ADD CONSTRAINT fk_product_info_packing_type_code FOREIGN KEY (packing_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE failure_description ADD CONSTRAINT fk_failure_description_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE failure_description ADD CONSTRAINT fk_failure_description_customer_failure_mode_code FOREIGN KEY (customer_failure_mode_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE sample ADD CONSTRAINT fk_sample_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE sample ADD CONSTRAINT fk_sample_failure_type_l1_code FOREIGN KEY (failure_type_l1_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE sample ADD CONSTRAINT fk_sample_failure_type_l2_code FOREIGN KEY (failure_type_l2_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE sample ADD CONSTRAINT fk_sample_failure_type_l3_code FOREIGN KEY (failure_type_l3_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE shipment ADD CONSTRAINT fk_shipment_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE shipment ADD CONSTRAINT fk_shipment_sender_id FOREIGN KEY (sender_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE shipment ADD CONSTRAINT fk_shipment_receiver_id FOREIGN KEY (receiver_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE shipment_sample ADD CONSTRAINT fk_shipment_sample_shipment_id FOREIGN KEY (shipment_id) REFERENCES shipment (shipment_id) ON DELETE CASCADE;
ALTER TABLE shipment_sample ADD CONSTRAINT fk_shipment_sample_sample_id FOREIGN KEY (sample_id) REFERENCES sample (sample_id) ON DELETE CASCADE;
ALTER TABLE verification_task ADD CONSTRAINT fk_verification_task_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE verification_task ADD CONSTRAINT fk_verification_task_sample_id FOREIGN KEY (sample_id) REFERENCES sample (sample_id) ON DELETE CASCADE;
ALTER TABLE verification_task ADD CONSTRAINT fk_verification_task_task_owner_id FOREIGN KEY (task_owner_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE verification_result ADD CONSTRAINT fk_verification_result_task_id FOREIGN KEY (task_id) REFERENCES verification_task (task_id) ON DELETE CASCADE;
ALTER TABLE verification_result ADD CONSTRAINT fk_verification_result_failure_type_l1_code FOREIGN KEY (failure_type_l1_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE verification_result ADD CONSTRAINT fk_verification_result_failure_type_l2_code FOREIGN KEY (failure_type_l2_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE verification_result ADD CONSTRAINT fk_verification_result_failure_type_l3_code FOREIGN KEY (failure_type_l3_code) REFERENCES failure_type (code) ON DELETE RESTRICT;
ALTER TABLE verification_result ADD CONSTRAINT fk_verification_result_recorded_by FOREIGN KEY (recorded_by) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE attachment ADD CONSTRAINT fk_attachment_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE containment_action ADD CONSTRAINT fk_containment_action_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE containment_action ADD CONSTRAINT fk_containment_action_owner_id FOREIGN KEY (owner_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE containment_action ADD CONSTRAINT fk_containment_action_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE root_cause ADD CONSTRAINT fk_root_cause_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE root_cause ADD CONSTRAINT fk_root_cause_responsible_org_code FOREIGN KEY (responsible_org_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE root_cause ADD CONSTRAINT fk_root_cause_transferred_to_id FOREIGN KEY (transferred_to_id) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE root_cause ADD CONSTRAINT fk_root_cause_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE why_analysis ADD CONSTRAINT fk_why_analysis_root_cause_id FOREIGN KEY (root_cause_id) REFERENCES root_cause (root_cause_id) ON DELETE CASCADE;
ALTER TABLE corrective_action ADD CONSTRAINT fk_corrective_action_root_cause_id FOREIGN KEY (root_cause_id) REFERENCES root_cause (root_cause_id) ON DELETE CASCADE;
ALTER TABLE corrective_action ADD CONSTRAINT fk_corrective_action_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE corrective_action ADD CONSTRAINT fk_corrective_action_owner_id FOREIGN KEY (owner_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE corrective_action ADD CONSTRAINT fk_corrective_action_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE action_verification ADD CONSTRAINT fk_action_verification_corrective_action_id FOREIGN KEY (corrective_action_id) REFERENCES corrective_action (corrective_action_id) ON DELETE CASCADE;
ALTER TABLE action_verification ADD CONSTRAINT fk_action_verification_verified_by FOREIGN KEY (verified_by) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE prevention_file_update ADD CONSTRAINT fk_prevention_file_update_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE prevention_file_update ADD CONSTRAINT fk_prevention_file_update_file_type_code FOREIGN KEY (file_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE prevention_file_update ADD CONSTRAINT fk_prevention_file_update_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE report_8d ADD CONSTRAINT fk_report_8d_complaint_id FOREIGN KEY (complaint_id) REFERENCES complaint (complaint_id) ON DELETE CASCADE;
ALTER TABLE report_step_owner ADD CONSTRAINT fk_report_step_owner_report_id FOREIGN KEY (report_id) REFERENCES report_8d (report_id) ON DELETE CASCADE;
ALTER TABLE report_step_owner ADD CONSTRAINT fk_report_step_owner_owner_id FOREIGN KEY (owner_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE report_step_owner ADD CONSTRAINT fk_report_step_owner_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE report_distribution ADD CONSTRAINT fk_report_distribution_report_id FOREIGN KEY (report_id) REFERENCES report_8d (report_id) ON DELETE CASCADE;
ALTER TABLE report_distribution ADD CONSTRAINT fk_report_distribution_sender_id FOREIGN KEY (sender_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE approval_task ADD CONSTRAINT fk_approval_task_approver_id FOREIGN KEY (approver_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE approval_task ADD CONSTRAINT fk_approval_task_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE contact_person ADD CONSTRAINT fk_contact_person_customer_code FOREIGN KEY (customer_code) REFERENCES customer (customer_code) ON DELETE RESTRICT;
ALTER TABLE ship_to_sold_to ADD CONSTRAINT fk_ship_to_sold_to_customer_code FOREIGN KEY (customer_code) REFERENCES customer (customer_code) ON DELETE RESTRICT;
ALTER TABLE product_master ADD CONSTRAINT fk_product_master_product_type_code FOREIGN KEY (product_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE product_master ADD CONSTRAINT fk_product_master_packing_type_code FOREIGN KEY (packing_type_code) REFERENCES master_data_item (code) ON DELETE RESTRICT;
ALTER TABLE employee ADD CONSTRAINT fk_employee_line_manager_id FOREIGN KEY (line_manager_id) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE production_master ADD CONSTRAINT fk_production_master_parent_id FOREIGN KEY (parent_id) REFERENCES production_master (pm_id) ON DELETE SET NULL;
ALTER TABLE master_data_item ADD CONSTRAINT fk_master_data_item_parent_id FOREIGN KEY (parent_id) REFERENCES master_data_item (md_id) ON DELETE SET NULL;
ALTER TABLE failure_type ADD CONSTRAINT fk_failure_type_parent_id FOREIGN KEY (parent_id) REFERENCES failure_type (failure_type_id) ON DELETE SET NULL;
ALTER TABLE role_permission ADD CONSTRAINT fk_role_permission_role_id FOREIGN KEY (role_id) REFERENCES role (role_id) ON DELETE RESTRICT;
ALTER TABLE role_permission ADD CONSTRAINT fk_role_permission_permission_id FOREIGN KEY (permission_id) REFERENCES permission (permission_id) ON DELETE RESTRICT;
ALTER TABLE user_role ADD CONSTRAINT fk_user_role_employee_id FOREIGN KEY (employee_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE user_role ADD CONSTRAINT fk_user_role_role_id FOREIGN KEY (role_id) REFERENCES role (role_id) ON DELETE RESTRICT;
ALTER TABLE audit_log ADD CONSTRAINT fk_audit_log_operator_id FOREIGN KEY (operator_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE system_announcement ADD CONSTRAINT fk_system_announcement_published_by FOREIGN KEY (published_by) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE notification_rule ADD CONSTRAINT fk_notification_rule_escalate_to_id FOREIGN KEY (escalate_to_id) REFERENCES employee (employee_id) ON DELETE SET NULL;
ALTER TABLE notification ADD CONSTRAINT fk_notification_recipient_id FOREIGN KEY (recipient_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE interface_log ADD CONSTRAINT fk_interface_log_interface_id FOREIGN KEY (interface_id) REFERENCES interface_config (interface_id) ON DELETE RESTRICT;
ALTER TABLE knowledge_article ADD CONSTRAINT fk_knowledge_article_source_complaint_id FOREIGN KEY (source_complaint_id) REFERENCES complaint (complaint_id) ON DELETE SET NULL;
ALTER TABLE knowledge_article ADD CONSTRAINT fk_knowledge_article_status_code FOREIGN KEY (status_code) REFERENCES status_code (status_code) ON DELETE RESTRICT;
ALTER TABLE knowledge_article_tag ADD CONSTRAINT fk_knowledge_article_tag_article_id FOREIGN KEY (article_id) REFERENCES knowledge_article (article_id) ON DELETE CASCADE;
ALTER TABLE knowledge_article_tag ADD CONSTRAINT fk_knowledge_article_tag_tag_id FOREIGN KEY (tag_id) REFERENCES knowledge_tag (tag_id) ON DELETE CASCADE;
ALTER TABLE subscription ADD CONSTRAINT fk_subscription_subscriber_id FOREIGN KEY (subscriber_id) REFERENCES employee (employee_id) ON DELETE RESTRICT;
ALTER TABLE subscription ADD CONSTRAINT fk_subscription_tag_id FOREIGN KEY (tag_id) REFERENCES knowledge_tag (tag_id) ON DELETE CASCADE;
ALTER TABLE report_config ADD CONSTRAINT fk_report_config_owner_id FOREIGN KEY (owner_id) REFERENCES employee (employee_id) ON DELETE SET NULL;

-- ===========================================================================
-- 索引
-- ===========================================================================
-- 每个外键列建索引：PostgreSQL 不会自动为外键建索引，缺索引会在 200 并发（3.15）下拖慢关联查询。
CREATE INDEX idx_complaint_status_code ON complaint (status_code);
CREATE INDEX idx_complaint_complaint_type_code ON complaint (complaint_type_code);
CREATE INDEX idx_complaint_priority_code ON complaint (priority_code);
CREATE INDEX idx_complaint_failure_location_code ON complaint (failure_location_code);
CREATE INDEX idx_complaint_complaint_owner_id ON complaint (complaint_owner_id);
CREATE INDEX idx_complaint_coordinator_id ON complaint (coordinator_id);
CREATE INDEX idx_complaint_verification_owner_id ON complaint (verification_owner_id);
CREATE INDEX idx_complaint_report_owner_id ON complaint (report_owner_id);
CREATE INDEX idx_quality_partner_complaint_id ON quality_partner (complaint_id);
CREATE INDEX idx_quality_partner_quality_partner_code ON quality_partner (quality_partner_code);
CREATE INDEX idx_quality_partner_contact_person_id ON quality_partner (contact_person_id);
CREATE INDEX idx_quality_partner_sub_segment_code ON quality_partner (sub_segment_code);
CREATE INDEX idx_quality_partner_ship_to_sold_to_code ON quality_partner (ship_to_sold_to_code);
CREATE INDEX idx_product_info_complaint_id ON product_info (complaint_id);
CREATE INDEX idx_product_info_material_code ON product_info (material_code);
CREATE INDEX idx_product_info_product_type_code ON product_info (product_type_code);
CREATE INDEX idx_product_info_packing_type_code ON product_info (packing_type_code);
CREATE INDEX idx_failure_description_complaint_id ON failure_description (complaint_id);
CREATE INDEX idx_failure_description_customer_failure_mode_code ON failure_description (customer_failure_mode_code);
CREATE INDEX idx_sample_complaint_id ON sample (complaint_id);
CREATE INDEX idx_sample_failure_type_l1_code ON sample (failure_type_l1_code);
CREATE INDEX idx_sample_failure_type_l2_code ON sample (failure_type_l2_code);
CREATE INDEX idx_sample_failure_type_l3_code ON sample (failure_type_l3_code);
CREATE INDEX idx_shipment_complaint_id ON shipment (complaint_id);
CREATE INDEX idx_shipment_sender_id ON shipment (sender_id);
CREATE INDEX idx_shipment_receiver_id ON shipment (receiver_id);
CREATE INDEX idx_shipment_sample_shipment_id ON shipment_sample (shipment_id);
CREATE INDEX idx_shipment_sample_sample_id ON shipment_sample (sample_id);
CREATE INDEX idx_verification_task_complaint_id ON verification_task (complaint_id);
CREATE INDEX idx_verification_task_sample_id ON verification_task (sample_id);
CREATE INDEX idx_verification_task_task_owner_id ON verification_task (task_owner_id);
CREATE INDEX idx_verification_result_task_id ON verification_result (task_id);
CREATE INDEX idx_verification_result_failure_type_l1_code ON verification_result (failure_type_l1_code);
CREATE INDEX idx_verification_result_failure_type_l2_code ON verification_result (failure_type_l2_code);
CREATE INDEX idx_verification_result_failure_type_l3_code ON verification_result (failure_type_l3_code);
CREATE INDEX idx_verification_result_recorded_by ON verification_result (recorded_by);
CREATE INDEX idx_attachment_uploaded_by ON attachment (uploaded_by);
CREATE INDEX idx_containment_action_complaint_id ON containment_action (complaint_id);
CREATE INDEX idx_containment_action_owner_id ON containment_action (owner_id);
CREATE INDEX idx_containment_action_status_code ON containment_action (status_code);
CREATE INDEX idx_root_cause_complaint_id ON root_cause (complaint_id);
CREATE INDEX idx_root_cause_responsible_org_code ON root_cause (responsible_org_code);
CREATE INDEX idx_root_cause_transferred_to_id ON root_cause (transferred_to_id);
CREATE INDEX idx_root_cause_status_code ON root_cause (status_code);
CREATE INDEX idx_why_analysis_root_cause_id ON why_analysis (root_cause_id);
CREATE INDEX idx_corrective_action_root_cause_id ON corrective_action (root_cause_id);
CREATE INDEX idx_corrective_action_complaint_id ON corrective_action (complaint_id);
CREATE INDEX idx_corrective_action_owner_id ON corrective_action (owner_id);
CREATE INDEX idx_corrective_action_status_code ON corrective_action (status_code);
CREATE INDEX idx_action_verification_corrective_action_id ON action_verification (corrective_action_id);
CREATE INDEX idx_action_verification_verified_by ON action_verification (verified_by);
CREATE INDEX idx_prevention_file_update_complaint_id ON prevention_file_update (complaint_id);
CREATE INDEX idx_prevention_file_update_file_type_code ON prevention_file_update (file_type_code);
CREATE INDEX idx_prevention_file_update_status_code ON prevention_file_update (status_code);
CREATE INDEX idx_report_8d_complaint_id ON report_8d (complaint_id);
CREATE INDEX idx_report_step_owner_report_id ON report_step_owner (report_id);
CREATE INDEX idx_report_step_owner_owner_id ON report_step_owner (owner_id);
CREATE INDEX idx_report_step_owner_status_code ON report_step_owner (status_code);
CREATE INDEX idx_report_distribution_report_id ON report_distribution (report_id);
CREATE INDEX idx_report_distribution_sender_id ON report_distribution (sender_id);
CREATE INDEX idx_approval_task_approver_id ON approval_task (approver_id);
CREATE INDEX idx_approval_task_status_code ON approval_task (status_code);
CREATE INDEX idx_contact_person_customer_code ON contact_person (customer_code);
CREATE INDEX idx_ship_to_sold_to_customer_code ON ship_to_sold_to (customer_code);
CREATE INDEX idx_product_master_product_type_code ON product_master (product_type_code);
CREATE INDEX idx_product_master_packing_type_code ON product_master (packing_type_code);
CREATE INDEX idx_employee_line_manager_id ON employee (line_manager_id);
CREATE INDEX idx_production_master_parent_id ON production_master (parent_id);
CREATE INDEX idx_master_data_item_parent_id ON master_data_item (parent_id);
CREATE INDEX idx_failure_type_parent_id ON failure_type (parent_id);
CREATE INDEX idx_role_permission_role_id ON role_permission (role_id);
CREATE INDEX idx_role_permission_permission_id ON role_permission (permission_id);
CREATE INDEX idx_user_role_employee_id ON user_role (employee_id);
CREATE INDEX idx_user_role_role_id ON user_role (role_id);
CREATE INDEX idx_audit_log_operator_id ON audit_log (operator_id);
CREATE INDEX idx_system_announcement_published_by ON system_announcement (published_by);
CREATE INDEX idx_notification_rule_escalate_to_id ON notification_rule (escalate_to_id);
CREATE INDEX idx_notification_recipient_id ON notification (recipient_id);
CREATE INDEX idx_interface_log_interface_id ON interface_log (interface_id);
CREATE INDEX idx_knowledge_article_source_complaint_id ON knowledge_article (source_complaint_id);
CREATE INDEX idx_knowledge_article_status_code ON knowledge_article (status_code);
CREATE INDEX idx_knowledge_article_tag_article_id ON knowledge_article_tag (article_id);
CREATE INDEX idx_knowledge_article_tag_tag_id ON knowledge_article_tag (tag_id);
CREATE INDEX idx_subscription_subscriber_id ON subscription (subscriber_id);
CREATE INDEX idx_subscription_tag_id ON subscription (tag_id);
CREATE INDEX idx_report_config_owner_id ON report_config (owner_id);

-- 高频查询与报表维度索引
-- 与外键索引同名同列的跳过：FK 索引已覆盖，重复建索引只会拖慢写入。
-- (skipped idx_complaint_status_code: same single column is already indexed by the FK index)
CREATE INDEX idx_complaint_target_date ON complaint (target_date) WHERE is_deleted = false;
CREATE INDEX idx_complaint_complaint_owner_id_status_code ON complaint (complaint_owner_id, status_code) WHERE is_deleted = false;
-- (skipped idx_complaint_coordinator_id: same single column is already indexed by the FK index)
CREATE INDEX idx_complaint_customer_reference_id ON complaint (customer_reference_id);
CREATE INDEX idx_complaint_created_at ON complaint (created_at);
CREATE INDEX idx_verification_task_task_owner_id_task_status ON verification_task (task_owner_id, task_status);
CREATE INDEX idx_verification_task_target_completion_date ON verification_task (target_completion_date);
CREATE INDEX idx_verification_result_failure_type_l1_code_failure_type_l2 ON verification_result (failure_type_l1_code, failure_type_l2_code, failure_type_l3_code);
CREATE INDEX idx_containment_action_owner_id_status_code ON containment_action (owner_id, status_code);
CREATE INDEX idx_corrective_action_owner_id_status_code ON corrective_action (owner_id, status_code);
CREATE INDEX idx_corrective_action_target_date ON corrective_action (target_date);
CREATE INDEX idx_report_8d_complaint_id_report_type ON report_8d (complaint_id, report_type);
CREATE INDEX idx_report_8d_approval_status ON report_8d (approval_status);
CREATE INDEX idx_report_step_owner_owner_id_status_code ON report_step_owner (owner_id, status_code);
CREATE INDEX idx_notification_recipient_id_send_status ON notification (recipient_id, send_status);
CREATE INDEX idx_interface_log_interface_id_called_at ON interface_log (interface_id, called_at);
CREATE INDEX idx_interface_log_call_status ON interface_log (call_status);
CREATE INDEX idx_audit_log_operator_id_created_at ON audit_log (operator_id, created_at);
CREATE INDEX idx_audit_log_biz_type_biz_id ON audit_log (biz_type, biz_id);
CREATE INDEX idx_master_data_item_md_type_is_active_sort_order ON master_data_item (md_type, is_active, sort_order);
CREATE INDEX idx_failure_type_level_no_parent_id_is_active ON failure_type (level_no, parent_id, is_active);
CREATE INDEX idx_attachment_biz_type_biz_id ON attachment (biz_type, biz_id);
CREATE INDEX idx_knowledge_article_category_status_code ON knowledge_article (category, status_code);

-- 模糊检索（3.11）三元组索引
CREATE INDEX idx_complaint_customer_reference_id_trgm ON complaint USING gin (customer_reference_id gin_trgm_ops);
CREATE INDEX idx_root_cause_root_cause_summary_trgm ON root_cause USING gin (root_cause_summary gin_trgm_ops);
CREATE INDEX idx_root_cause_root_cause_desc_trgm ON root_cause USING gin (root_cause_desc gin_trgm_ops);
CREATE INDEX idx_failure_description_customer_failure_description_trgm ON failure_description USING gin (customer_failure_description gin_trgm_ops);
CREATE INDEX idx_knowledge_article_title_trgm ON knowledge_article USING gin (title gin_trgm_ops);

-- ===========================================================================
-- updated_at 触发器
-- ===========================================================================
CREATE TRIGGER trg_customer_updated_at BEFORE UPDATE ON customer FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_contact_person_updated_at BEFORE UPDATE ON contact_person FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ship_to_sold_to_updated_at BEFORE UPDATE ON ship_to_sold_to FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_employee_updated_at BEFORE UPDATE ON employee FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_production_master_updated_at BEFORE UPDATE ON production_master FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_master_data_item_updated_at BEFORE UPDATE ON master_data_item FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_failure_type_updated_at BEFORE UPDATE ON failure_type FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_status_code_updated_at BEFORE UPDATE ON status_code FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_role_updated_at BEFORE UPDATE ON role FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_permission_updated_at BEFORE UPDATE ON permission FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_role_permission_updated_at BEFORE UPDATE ON role_permission FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_user_role_updated_at BEFORE UPDATE ON user_role FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_audit_log_updated_at BEFORE UPDATE ON audit_log FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_system_announcement_updated_at BEFORE UPDATE ON system_announcement FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notification_rule_updated_at BEFORE UPDATE ON notification_rule FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notification_updated_at BEFORE UPDATE ON notification FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_interface_config_updated_at BEFORE UPDATE ON interface_config FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_interface_log_updated_at BEFORE UPDATE ON interface_log FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_knowledge_tag_updated_at BEFORE UPDATE ON knowledge_tag FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_subscription_updated_at BEFORE UPDATE ON subscription FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_report_config_updated_at BEFORE UPDATE ON report_config FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_complaint_updated_at BEFORE UPDATE ON complaint FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_quality_partner_updated_at BEFORE UPDATE ON quality_partner FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_failure_description_updated_at BEFORE UPDATE ON failure_description FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_sample_updated_at BEFORE UPDATE ON sample FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_shipment_updated_at BEFORE UPDATE ON shipment FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_shipment_sample_updated_at BEFORE UPDATE ON shipment_sample FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_verification_task_updated_at BEFORE UPDATE ON verification_task FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_verification_result_updated_at BEFORE UPDATE ON verification_result FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_attachment_updated_at BEFORE UPDATE ON attachment FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_containment_action_updated_at BEFORE UPDATE ON containment_action FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_root_cause_updated_at BEFORE UPDATE ON root_cause FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_why_analysis_updated_at BEFORE UPDATE ON why_analysis FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_corrective_action_updated_at BEFORE UPDATE ON corrective_action FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_action_verification_updated_at BEFORE UPDATE ON action_verification FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_prevention_file_update_updated_at BEFORE UPDATE ON prevention_file_update FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_report_8d_updated_at BEFORE UPDATE ON report_8d FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_report_step_owner_updated_at BEFORE UPDATE ON report_step_owner FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_report_distribution_updated_at BEFORE UPDATE ON report_distribution FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_approval_task_updated_at BEFORE UPDATE ON approval_task FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_product_master_updated_at BEFORE UPDATE ON product_master FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_knowledge_article_updated_at BEFORE UPDATE ON knowledge_article FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_knowledge_article_tag_updated_at BEFORE UPDATE ON knowledge_article_tag FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_product_info_updated_at BEFORE UPDATE ON product_info FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================================================
-- 视图：我的待办（首页工作台，3.0）
-- 依赖字典表 status_code.is_final 判定终态，避免在视图里硬编码状态码。
-- ===========================================================================
CREATE OR REPLACE VIEW v_todo AS
SELECT 'VERIFICATION'::text AS todo_type, 'VerificationTask'::text AS biz_type,
       vt.task_id AS biz_id, vt.task_owner_id AS owner_id, vt.target_completion_date AS due_at
  FROM verification_task vt
  LEFT JOIN status_code sc ON sc.status_code = vt.task_status
 WHERE vt.completed_at IS NULL AND vt.is_deleted = false AND coalesce(sc.is_final, false) = false
UNION ALL
SELECT 'APPROVAL', 'ApprovalTask', at.approval_id, at.approver_id, NULL::date
  FROM approval_task at
  LEFT JOIN status_code sc ON sc.status_code = at.status_code
 WHERE at.completed_at IS NULL AND at.is_deleted = false AND coalesce(sc.is_final, false) = false
UNION ALL
SELECT 'CORRECTIVE_ACTION', 'CorrectiveAction', ca.corrective_action_id, ca.owner_id, ca.target_date
  FROM corrective_action ca
  LEFT JOIN status_code sc ON sc.status_code = ca.status_code
 WHERE ca.is_deleted = false AND coalesce(sc.is_final, false) = false
UNION ALL
SELECT 'CONTAINMENT_ACTION', 'ContainmentAction', coa.action_id, coa.owner_id, coa.completed_date
  FROM containment_action coa
  LEFT JOIN status_code sc ON sc.status_code = coa.status_code
 WHERE coa.completed_date IS NULL AND coa.is_deleted = false AND coalesce(sc.is_final, false) = false
UNION ALL
SELECT 'PREVENTION_FILE', 'PreventionFileUpdate', pfu.update_id::text, c.complaint_owner_id, NULL::date
  FROM prevention_file_update pfu
  JOIN complaint c ON c.complaint_id = pfu.complaint_id
  LEFT JOIN status_code sc ON sc.status_code = pfu.status_code
 WHERE pfu.is_deleted = false AND coalesce(sc.is_final, false) = false
UNION ALL
SELECT 'REPORT_STEP', 'ReportStepOwner', rso.step_owner_id::text, rso.owner_id, NULL::date
  FROM report_step_owner rso
  LEFT JOIN status_code sc ON sc.status_code = rso.status_code
 WHERE rso.completed_at IS NULL AND rso.is_deleted = false AND coalesce(sc.is_final, false) = false;
COMMENT ON VIEW v_todo IS '我的待办：由各业务表按负责人聚合，不含权限过滤，应用层按 owner_id 过滤当前登录用户';

-- ===========================================================================
-- 字典种子数据
-- 说明：编码为占位规则（<类型>_001 递增），中文名取自需求文档；
--       正式编码请由业务方确认后替换。
-- ===========================================================================

-- QMS 平台主数据项（master_data_item）
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_001', '技术投诉-复杂', 'QMS', 1, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_002', '技术投诉-非复杂', 'QMS', 2, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_003', '物流投诉', 'QMS', 3, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_004', '商务投诉', 'QMS', 4, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_005', '分析申请', 'QMS', 5, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('complaint_type', 'COMPLAINT_TYPE_006', '内部投诉', 'QMS', 6, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('priority', 'PRIORITY_001', '标准', 'QMS', 1, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('priority', 'PRIORITY_002', '紧急', 'QMS', 2, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('priority', 'PRIORITY_003', '非常紧急', 'QMS', 3, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('failure_location', 'FAILURE_LOCATION_001', '应用测试', 'QMS', 1, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('failure_location', 'FAILURE_LOCATION_002', '产线拒收', 'QMS', 2, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('failure_location', 'FAILURE_LOCATION_003', '可靠性监控 等', 'QMS', 3, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('file_type', 'FILE_TYPE_001', 'FMEA', 'QMS', 1, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('file_type', 'FILE_TYPE_002', 'Control Plan', 'QMS', 2, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('file_type', 'FILE_TYPE_003', 'OCAP', 'QMS', 3, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('file_type', 'FILE_TYPE_004', 'SOP', 'QMS', 4, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('file_type', 'FILE_TYPE_005', 'Update on Flow', 'QMS', 5, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('responsible_org', 'RESPONSIBLE_ORG_001', '内部', 'QMS', 1, true) ON CONFLICT (code) DO NOTHING;
INSERT INTO master_data_item (md_type, code, name_cn, source_system, sort_order, is_active) VALUES ('responsible_org', 'RESPONSIBLE_ORG_002', '外部根因组织', 'QMS', 2, true) ON CONFLICT (code) DO NOTHING;
-- sub_segment：主数据取值清单文档未给出，待业务方补充
-- product_type：主数据取值清单文档未给出，待业务方补充
-- packing_type：主数据取值清单文档未给出，待业务方补充

-- 状态码字典（status_code）
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S01', 'Complaint', '登记-已启动', 1, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S02', 'Complaint', '验证-已排期', 2, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S03', 'Complaint', '验证中', 3, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S04', 'Complaint', '分析中', 4, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S05', 'Complaint', '措施中', 5, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S06', 'Complaint', '报告编制中', 6, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('COMPLAINT_S07', 'Complaint', '已结案', 7, true) ON CONFLICT (status_code) DO NOTHING;
-- 其他实体的状态码文档未逐一定义，按通用四态占位，待业务方确认后替换：
-- 注意：占位状态必须先插入，否则业务表状态字段 FK 无法指向。
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('GENERIC_OPEN', 'GENERIC', '待处理', 1, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('GENERIC_DOING', 'GENERIC', '进行中', 2, false) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('GENERIC_DONE', 'GENERIC', '已完成', 3, true) ON CONFLICT (status_code) DO NOTHING;
INSERT INTO status_code (status_code, entity_name, name_cn, sort_order, is_final) VALUES ('GENERIC_CLOSED', 'GENERIC', '已关闭', 4, true) ON CONFLICT (status_code) DO NOTHING;

-- 失效类型三级主数据（failure_type）
-- 取值来自需求文档内嵌电子表格示例（3.3）
INSERT INTO failure_type (level_no, code, name, is_active) VALUES (1, '2', '2 - Assembly related', true) ON CONFLICT (code) DO NOTHING;
INSERT INTO failure_type (level_no, code, name, parent_id, is_active) SELECT 2, '2a', '2a - Bond and wire', failure_type_id, true FROM failure_type WHERE code = '2' ON CONFLICT (code) DO NOTHING;
INSERT INTO failure_type (level_no, code, name, parent_id, is_active) SELECT 3, '2aa', '2aa - Lifted ball bond', failure_type_id, true FROM failure_type WHERE code = '2a' ON CONFLICT (code) DO NOTHING;
INSERT INTO failure_type (level_no, code, name, parent_id, is_active) SELECT 3, '2ab', '2ab - Broken ball neck', failure_type_id, true FROM failure_type WHERE code = '2a' ON CONFLICT (code) DO NOTHING;

-- ===========================================================================
-- 安装后自检
-- ===========================================================================
SELECT count(*) AS tables_created FROM information_schema.tables WHERE table_schema = 'qms' AND table_type = 'BASE TABLE';
SELECT conname AS foreign_keys FROM pg_constraint WHERE contype = 'f' ORDER BY 1;
SELECT count(*) AS indexes_created FROM pg_indexes WHERE schemaname = 'qms';
-- 外键孤儿检查（应全部返回 0）：
SELECT count(*) AS orphan_complaint_owner FROM complaint c LEFT JOIN employee e ON e.employee_id = c.complaint_owner_id WHERE e.employee_id IS NULL;
