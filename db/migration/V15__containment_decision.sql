-- ===========================================================================
-- V15 D3 是否需要遏制的判断（追加迁移）
-- ===========================================================================
-- PS-039 要求 D3 先「判断是否需要遏制」。这个判断是个真实的分支：不需要时 D3
-- 整个跳过，流程直接进 D4。基线没有存储它的地方，而仅靠审计日志无法区分
-- 「已判断为不需要」与「尚未开始 D3」——阶段条上也看不出差别。
--
-- 因此加两列，与 V6 加 current_stage 是同一个理由。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE complaint ADD COLUMN containment_required boolean;
ALTER TABLE complaint ADD COLUMN containment_decision_note text;

COMMENT ON COLUMN complaint.containment_required IS
    '是否需要遏制措施 | NULL=尚未判断；true=需要（D3 已启动）；false=不需要（流程直接进 D4）。对应 PS-039';
COMMENT ON COLUMN complaint.containment_decision_note IS
    '遏制判断说明 | 记录判断理由，尤其是判定为「不需要」时的依据';
