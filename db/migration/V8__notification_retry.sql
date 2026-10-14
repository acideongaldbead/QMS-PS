-- ===========================================================================
-- V8 通知发件箱重试字段（追加迁移）
-- ===========================================================================
-- 基线 notification 只有 send_status / error_msg，没有重试所需的计数与下次时间。
-- 发件箱模式（事务内写 PENDING，定时任务领取发送、失败退避重试）需要这两列。
-- ===========================================================================

SET search_path TO qms, public;

ALTER TABLE notification ADD COLUMN retry_count   integer NOT NULL DEFAULT 0;
ALTER TABLE notification ADD COLUMN next_retry_at timestamptz;

COMMENT ON COLUMN notification.retry_count IS '已重试次数 | 达到上限后不再重试并标记失败';
COMMENT ON COLUMN notification.next_retry_at IS '下次重试时间 | 退避重试的调度时间；空表示立即可取';

-- 定时任务按「待发送 + 到点」扫描，这个部分索引避免全表扫。
CREATE INDEX idx_notification_pending ON notification (send_status, next_retry_at) WHERE is_deleted = false;
