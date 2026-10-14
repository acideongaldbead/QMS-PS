-- ===========================================================================
-- V6 投诉单增加 8D 阶段列（追加迁移）
-- ===========================================================================
-- complaint.status_code 只有 7 个状态值，而界面需要的 8D 阶段有 9 个（D0-D8），
-- 两者不是一一对应（例如 S02/S03 都落在 D2）。所以另开一列存阶段，状态仍表达
-- 「流程节点 + 子状态」的两段式口径（与需求 3.1.2 示例一致）。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE complaint ADD COLUMN current_stage varchar(4);

UPDATE complaint SET current_stage = CASE status_code
    WHEN 'COMPLAINT_S01' THEN 'D0'
    WHEN 'COMPLAINT_S02' THEN 'D2'
    WHEN 'COMPLAINT_S03' THEN 'D2'
    WHEN 'COMPLAINT_S04' THEN 'D4'
    WHEN 'COMPLAINT_S05' THEN 'D5'
    WHEN 'COMPLAINT_S06' THEN 'D8'
    WHEN 'COMPLAINT_S07' THEN 'D8'
    ELSE 'D0'
END;

ALTER TABLE complaint ALTER COLUMN current_stage SET DEFAULT 'D0';
ALTER TABLE complaint ALTER COLUMN current_stage SET NOT NULL;
ALTER TABLE complaint ADD CONSTRAINT ck_complaint_stage
    CHECK (current_stage IN ('D0','D1','D2','D3','D4','D5','D6','D7','D8'));

COMMENT ON COLUMN complaint.current_stage IS '当前8D阶段 | D0-D8；与 status_code 两段式并存，阶段由工作流按事件推进';

CREATE INDEX idx_complaint_stage ON complaint (current_stage) WHERE is_deleted = false;
