-- ===========================================================================
-- V14 修正投诉日期约束（追加迁移）
-- ===========================================================================
-- 基线写的是：CHECK (close_date IS NULL OR close_date >= start_date)。
--
-- 但 start_date 的默认值是「创建日期 + 7 天」（需求 3.1.2），而需求 2.1 明确要求
-- D2 判定「投诉不成立」时**直接结案**。此时结案日期必然早于开始日期，插入被这条
-- CHECK 挡下 —— 也就是说这个约束与需求里的分支互相矛盾。
--
-- 该约束真正的语义应当是「不能结案在立案之前」。改成与 created_at 比较：
--   * 异常早结案（无效判定）可以通过；
--   * 仍然挡住真正的数据录入错误（结案早于立案）；
--   * 正常路径（报告批准后结案，晚于 start_date）不受影响。
--
-- 选择改约束而不是回写用户的 start_date：后者会悄悄改掉业务人员填过的数据。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE complaint DROP CONSTRAINT ck_complaint_dates;

ALTER TABLE complaint ADD CONSTRAINT ck_complaint_dates
    CHECK (close_date IS NULL OR close_date >= created_at::date);

COMMENT ON CONSTRAINT ck_complaint_dates ON complaint IS
    '结案日期不得早于立案日期。刻意不与 start_date 比较：start_date 默认是立案后 7 天，而无效投诉可在 D2 直接结案，那时结案日会早于 start_date';
