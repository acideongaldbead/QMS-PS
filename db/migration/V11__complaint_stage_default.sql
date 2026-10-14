-- ===========================================================================
-- V11 修正投诉阶段默认值（追加迁移）
-- ===========================================================================
-- V6 把 current_stage 的默认值设为 D0，但业务确认（2026-10-13）后登记直接落在
-- D1「成立团队」——登记表单采集的正是该阶段要求的跨职能角色。应用层始终显式写入
-- D1，所以默认值只是兜底；但默认值与实际行为不一致会误导后来者，这里对齐。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE complaint ALTER COLUMN current_stage SET DEFAULT 'D1';
COMMENT ON COLUMN complaint.current_stage IS '当前8D阶段 | D0-D8；默认 D1，因为登记即完成「成立团队」，D0 含在登记动作内';

-- Rows written while the default was D0 but that never advanced would be
-- indistinguishable from a genuine D0, so nothing is rewritten here.
