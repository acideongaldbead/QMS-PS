-- ===========================================================================
-- V18 公告已读（追加迁移）
-- ===========================================================================
-- 首页公告的「NEW」标识需要知道「这个人对这条公告读没读过」。记在服务端而不是
-- 浏览器里：换设备、换浏览器不该让已读的公告重新变回未读。
--
-- 粒度是「公告 × 人」，主键即二者组合；读标记只新增不改写，所以用
-- ON CONFLICT DO NOTHING 保证幂等（重复点击不报错、不覆盖首次阅读时间）。
-- ===========================================================================

SET search_path TO qms, public;

CREATE TABLE IF NOT EXISTS announcement_read (
    announcement_id          bigint       NOT NULL,
    employee_id              varchar(32)  NOT NULL,
    read_at                  timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_announcement_read PRIMARY KEY (announcement_id, employee_id)
);
COMMENT ON TABLE announcement_read IS '公告已读 | 每条公告对每个人是否已读，首页 NEW 标识的依据。';
COMMENT ON COLUMN announcement_read.announcement_id IS '公告ID | 所属公告 | FK';
COMMENT ON COLUMN announcement_read.employee_id IS '员工ID | 阅读人 | FK';
COMMENT ON COLUMN announcement_read.read_at IS '首次阅读时间 | 只记第一次，重复点击不覆盖';

ALTER TABLE announcement_read
    ADD CONSTRAINT fk_announcement_read_announcement
    FOREIGN KEY (announcement_id) REFERENCES system_announcement (announcement_id) ON DELETE CASCADE;
ALTER TABLE announcement_read
    ADD CONSTRAINT fk_announcement_read_employee
    FOREIGN KEY (employee_id) REFERENCES employee (employee_id) ON DELETE CASCADE;

-- 首页每次都按「我是谁」过滤，按人建索引。
CREATE INDEX IF NOT EXISTS idx_announcement_read_employee
    ON announcement_read (employee_id);
