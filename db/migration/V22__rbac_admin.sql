-- ===========================================================================
-- V22 RBAC 管理界面（需求 3.12 权限管理）
-- ===========================================================================
-- 把角色与权限从「迁移种进去的固定数据」变成界面可维护的数据：管理员要建自定义
-- 角色、复制预设角色、勾选权限、给人配角色。
--
-- 本次**不需要任何新表或新列**：
--   · role / permission / role_permission / user_role 四张表结构早已齐备；
--   · user_account 的 is_active / failed_attempts / locked_until / must_change_pwd
--     在 V2 就建好了；
--   · role_type 与 permission_level 没有 CHECK 约束，自定义角色类型可直接写；
--   · 不新增权限码 —— 复用既有的 rbac:manage。
--
-- 唯一必须修的 schema 问题是唯一约束的形态。基线把 uq_role_code / uq_role_name
-- 声明成普通 UNIQUE，而 role 是软删除表：自定义角色被删除后，那一行仍然占着名称
-- 与编码，同名角色永远建不回来（与 V12 修 uq_shipment_sample 完全同源）。换成
-- 部分唯一索引后，约束只作用于存活行，删掉的角色不再占号。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE role DROP CONSTRAINT uq_role_code;
ALTER TABLE role DROP CONSTRAINT uq_role_name;

CREATE UNIQUE INDEX uq_role_code_live ON role (role_code) WHERE is_deleted = false;

CREATE UNIQUE INDEX uq_role_name_live ON role (role_name) WHERE is_deleted = false;

COMMENT ON INDEX qms.uq_role_code_live IS
    '存活角色的编码唯一 | 软删除的角色不参与约束，故删除后可用同一编码重建';

COMMENT ON INDEX qms.uq_role_name_live IS
    '存活角色的名称唯一 | 软删除的角色不参与约束，故删除后可用同一名称重建';
