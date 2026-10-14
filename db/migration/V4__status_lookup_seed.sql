-- ===========================================================================
-- V4 状态码补全（追加迁移）
-- ===========================================================================
-- 基线只种了 Complaint 的 7 个状态 + 4 个 GENERIC_* 占位。但有 8 张表的
-- status_code 字段带外键指向本表，它们目前**只能指向 GENERIC_* 占位值**。
-- 本迁移为每个实体补出真实状态码，并给已有行补 name_en（供中英文切换）。
--
-- 只新增、不改名、不删除：基线注释明确说明占位码是待确认项，且已被外键引用。
-- ===========================================================================

SET search_path TO qms, public;

-- ---------------------------------------------------------------- 已有行补英文名
UPDATE status_code SET name_en = 'Registration started'     WHERE status_code = 'COMPLAINT_S01';
UPDATE status_code SET name_en = 'Verification scheduled'   WHERE status_code = 'COMPLAINT_S02';
UPDATE status_code SET name_en = 'Verification in progress' WHERE status_code = 'COMPLAINT_S03';
UPDATE status_code SET name_en = 'Analysis in progress'     WHERE status_code = 'COMPLAINT_S04';
UPDATE status_code SET name_en = 'Actions in progress'      WHERE status_code = 'COMPLAINT_S05';
UPDATE status_code SET name_en = 'Report drafting'          WHERE status_code = 'COMPLAINT_S06';
UPDATE status_code SET name_en = 'Closed'                   WHERE status_code = 'COMPLAINT_S07';
UPDATE status_code SET name_en = 'Open'                     WHERE status_code = 'GENERIC_OPEN';
UPDATE status_code SET name_en = 'In progress'              WHERE status_code = 'GENERIC_DOING';
UPDATE status_code SET name_en = 'Done'                     WHERE status_code = 'GENERIC_DONE';
UPDATE status_code SET name_en = 'Closed'                   WHERE status_code = 'GENERIC_CLOSED';

-- ---------------------------------------------------------------- 遏制措施 D3
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('CONTAIN_TODO',       'ContainmentAction', '待处理',  'To do',          1, false),
    ('CONTAIN_DOING',      'ContainmentAction', '进行中',  'In progress',    2, false),
    ('CONTAIN_DONE',       'ContainmentAction', '已完成',  'Completed',      3, true),
    ('CONTAIN_CANCELLED',  'ContainmentAction', '已取消',  'Cancelled',      4, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 根因分析 D4
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('ROOTCAUSE_TODO',  'RootCause', '待分析', 'To analyse',    1, false),
    ('ROOTCAUSE_DOING', 'RootCause', '分析中', 'Analysing',     2, false),
    ('ROOTCAUSE_DONE',  'RootCause', '已完成', 'Completed',     3, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 纠正措施 D5/D6
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('CORR_TODO',     'CorrectiveAction', '待处理',   'To do',            1, false),
    ('CORR_DOING',    'CorrectiveAction', '进行中',   'In progress',      2, false),
    ('CORR_DONE',     'CorrectiveAction', '已实施',   'Implemented',      3, false),
    ('CORR_VERIFIED', 'CorrectiveAction', '已验证',   'Verified',         4, true),
    ('CORR_FAILED',   'CorrectiveAction', '验证不通过','Verification failed', 5, false)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 预防再发生 D7
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('PREV_TODO',  'PreventionFileUpdate', '待更新', 'To update',   1, false),
    ('PREV_DOING', 'PreventionFileUpdate', '更新中', 'Updating',    2, false),
    ('PREV_DONE',  'PreventionFileUpdate', '已完成', 'Completed',   3, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 报告步骤 D1-D8
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('STEP_TODO',    'ReportStepOwner', '待处理', 'To do',       1, false),
    ('STEP_WRITING', 'ReportStepOwner', '编写中', 'Drafting',    2, false),
    ('STEP_DONE',    'ReportStepOwner', '已完成', 'Completed',   3, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 审批任务
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('APPROVAL_PENDING',   'ApprovalTask', '待审批', 'Pending',    1, false),
    ('APPROVAL_APPROVED',  'ApprovalTask', '已批准', 'Approved',   2, true),
    ('APPROVAL_REJECTED',  'ApprovalTask', '已驳回', 'Rejected',   3, true),
    ('APPROVAL_WITHDRAWN', 'ApprovalTask', '已撤回', 'Withdrawn',  4, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;

-- ---------------------------------------------------------------- 知识条目
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('ARTICLE_DRAFT',     'KnowledgeArticle', '草稿',   'Draft',     1, false),
    ('ARTICLE_PUBLISHED', 'KnowledgeArticle', '已发布', 'Published', 2, true),
    ('ARTICLE_ARCHIVED',  'KnowledgeArticle', '已归档', 'Archived',  3, true)
ON CONFLICT (status_code) DO UPDATE SET name_en = EXCLUDED.name_en, name_cn = EXCLUDED.name_cn;
