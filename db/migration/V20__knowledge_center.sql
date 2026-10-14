-- ===========================================================================
-- V20 知识中心（需求 3.11，阶段 2.12）
-- ===========================================================================
-- 基线已有 knowledge_article（title / category / content + 审计列），但没有原型
-- 界面要展示的文档编号、英文标题、版本号与描述，本迁移补齐这四列。
--
-- 分类不落自由文本，种进 master_data_item（与 D7 的 file_type 同一套做法，以后
-- 加分类是改数据不是改代码）。取值按原型 kb.html 的四个页签：流程文件 / 分析模板
-- / 培训教材 / 操作手册。「问题解决经验」属经验分享，需求 1.5 明确排除出一期，不种。
--
-- 维护权限新增 knowledge:manage（功能按钮级），只给管理员。
-- 注意：V3 给管理员那批权限是当时 CROSS JOIN 的全量快照，本迁移新增的码不会自动
-- 落到管理员头上，必须显式补一条 role_permission。
--
-- 标签 / 订阅 / 结案后沉淀经验（knowledge_tag / knowledge_article_tag /
-- subscription / source_complaint_id）属二期经验分享，本轮不涉及。
-- ===========================================================================

SET search_path TO qms, public;

-- ---------------------------------------------------------------- 正文之外的新列
ALTER TABLE knowledge_article ADD COLUMN doc_code varchar(32);
ALTER TABLE knowledge_article ADD COLUMN title_en varchar(255);
ALTER TABLE knowledge_article ADD COLUMN version  varchar(16);
ALTER TABLE knowledge_article ADD COLUMN summary  varchar(500);

COMMENT ON COLUMN knowledge_article.doc_code IS '文档编号 | 如 XPR-0036，界面可检索，同表内唯一';
COMMENT ON COLUMN knowledge_article.title_en IS '标题(英) | 英文标题，对应中英文切换（3.17）';
COMMENT ON COLUMN knowledge_article.version IS '版本号 | 如 V4.0，由维护人填写；历史版本以历次上传的附件承载';
COMMENT ON COLUMN knowledge_article.summary IS '描述 | 一句话说明，列表第二行';

-- 文档编号唯一。必须是部分唯一索引：软删除的行不能永久占着编号（同 V12 换掉
-- uq_shipment_sample 的理由），且允许早期条目没有编号。
CREATE UNIQUE INDEX uq_knowledge_article_doc_code
    ON knowledge_article (doc_code)
 WHERE is_deleted = false AND doc_code IS NOT NULL;

-- ---------------------------------------------------------------- 分类字典
-- code 在全表唯一（uq_master_data_item_code），用 KNOWLEDGE_CATEGORY_nnn 前缀避免撞号。
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('knowledge_category', 'KNOWLEDGE_CATEGORY_001', '流程文件', 'Process document',  'QMS', 1, true),
    ('knowledge_category', 'KNOWLEDGE_CATEGORY_002', '分析模板', 'Analysis template', 'QMS', 2, true),
    ('knowledge_category', 'KNOWLEDGE_CATEGORY_003', '培训教材', 'Training material', 'QMS', 3, true),
    ('knowledge_category', 'KNOWLEDGE_CATEGORY_004', '操作手册', 'User manual',       'QMS', 4, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- 维护权限
INSERT INTO permission (permission_code, permission_name, permission_name_en, permission_level, module_code) VALUES
    ('knowledge:manage', '维护知识中心', 'Manage knowledge', 'BUTTON', 'KNOWLEDGE')
ON CONFLICT (permission_code) DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM role r CROSS JOIN permission p
WHERE r.role_code = 'ROLE_ADMINISTRATOR'
  AND p.permission_code = 'knowledge:manage'
ON CONFLICT (role_id, permission_id) DO NOTHING;
