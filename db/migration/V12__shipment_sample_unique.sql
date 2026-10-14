-- ===========================================================================
-- V12 修正物流样品关联的唯一约束（追加迁移）
-- ===========================================================================
-- 基线把 uq_shipment_sample 声明为普通的 UNIQUE (shipment_id, sample_id)。
-- 但整张表走的是软删除：把样品从批次里移除只是把 is_deleted 置为 true，
-- 那一行仍然占着唯一键 —— 结果是**该样品再也无法被加回同一批次**，
-- 插入会撞唯一约束并被当成"记录已存在"。
--
-- 换成部分唯一索引：约束只作用于存活的行，既保住了"一个批次里同一个样品
-- 只能出现一次"的意图，又允许移除后重新加入。基线的索引已经大量使用
-- 「WHERE is_deleted = false」的写法，这里与之一致。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE shipment_sample DROP CONSTRAINT uq_shipment_sample;

CREATE UNIQUE INDEX uq_shipment_sample_live
    ON shipment_sample (shipment_id, sample_id)
    WHERE is_deleted = false;

COMMENT ON INDEX qms.uq_shipment_sample_live IS
    '一个物流批次内同一存活样品只能出现一次；软删除的行不参与约束，故移除后可重新加入';
