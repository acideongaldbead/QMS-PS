-- ===========================================================================
-- V13 D2 验证所需的状态码与结案原因（追加迁移）
-- ===========================================================================
-- 两处基线里没有字典、但界面需要展示名的地方：
--   1. verification_task.task_status —— 自由文本，无外键
--   2. complaint.close_reason_code   —— 自由文本，DDL 注释已写明三个取值
-- 按 schema 自身约定（「字典类字段在业务表只存 code，展示名取自字典表」），
-- 这里把取值登记为词条来源。同样刻意不加外键，避免改变既有模型。
-- ===========================================================================

SET search_path TO qms, public;

-- ---------------------------------------------------------------- 验证任务状态
INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('VERIF_TODO',      'VerificationTask', '待排期', 'Not scheduled', 1, false),
    ('VERIF_SCHEDULED', 'VerificationTask', '已排期', 'Scheduled',     2, false),
    ('VERIF_DOING',     'VerificationTask', '验证中', 'In progress',   3, false),
    ('VERIF_DONE',      'VerificationTask', '已完成', 'Completed',     4, true),
    ('VERIF_CANCELLED', 'VerificationTask', '已取消', 'Cancelled',     5, true)
ON CONFLICT (status_code) DO UPDATE
    SET name_cn = EXCLUDED.name_cn, name_en = EXCLUDED.name_en;

-- ---------------------------------------------------------------- 结案原因
-- 取值来自基线对 complaint.close_reason_code 的注释：正常闭环 / 投诉不成立 / 转交根因组织。
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('close_reason', 'CLOSE_NORMAL',      '正常闭环',     'Closed normally',            'QMS', 1, true),
    ('close_reason', 'CLOSE_INVALID',     '投诉不成立',   'Complaint not valid',        'QMS', 2, true),
    ('close_reason', 'CLOSE_TRANSFERRED', '转交根因组织', 'Transferred to root cause',  'QMS', 3, true)
ON CONFLICT (code) DO UPDATE
    SET name_cn = EXCLUDED.name_cn, name_en = EXCLUDED.name_en;
