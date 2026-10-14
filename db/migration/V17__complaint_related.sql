-- ===========================================================================
-- V17 「与我相关」判定函数（追加迁移）
-- ===========================================================================
-- 台账「与我相关」页签与首页「与我相关投诉」展示的是同一个集合，两处必须口径
-- 一致；判定本身横跨 complaint 主表的 4 个责任人字段 + 发起人 + 7 张阶段子表的
-- owner，若在 SQL 里各写一遍，迟早会漂移。因此收进一个函数，列表查询、计数与
-- 首页聚合都调它，判定只有一处定义。
--
-- 口径（2026-10-14 业务确认，最宽）：本人是
--   投诉负责人 / 协调人 / 验证负责人 / 报告负责人 / 发起人，
-- 或该单下任一阶段任务的负责人（验证任务、遏制措施、根因转交对象、纠正措施、
-- 措施验证人、报告创建人、物流收发件人）。
--
-- 用 STABLE 而非 IMMUTABLE：函数读表，同一条语句内结果稳定即可。
--
-- 表名一律写全 qms. 前缀：SQL 函数会被内联进调用它的查询，而内联后用的是**调用方
-- 会话**的 search_path。应用连接设了 search_path，但手工 psql 或运维查询没有，
-- 不限定前缀就会在那类会话里报「关系 complaint 不存在」。
-- ===========================================================================

SET search_path TO qms, public;

CREATE OR REPLACE FUNCTION complaint_related(p_complaint_id varchar, p_employee_id varchar)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM qms.complaint c
         WHERE c.complaint_id = p_complaint_id
           AND (
                 c.complaint_owner_id     = p_employee_id
              OR c.coordinator_id         = p_employee_id
              OR c.verification_owner_id  = p_employee_id
              OR c.report_owner_id        = p_employee_id
              OR c.created_by             = p_employee_id
              OR EXISTS (SELECT 1 FROM qms.verification_task t
                          WHERE t.complaint_id = c.complaint_id AND t.is_deleted = false
                            AND t.task_owner_id = p_employee_id)
              OR EXISTS (SELECT 1 FROM qms.containment_action ca
                          WHERE ca.complaint_id = c.complaint_id AND ca.is_deleted = false
                            AND ca.owner_id = p_employee_id)
              OR EXISTS (SELECT 1 FROM qms.root_cause rc
                          WHERE rc.complaint_id = c.complaint_id AND rc.is_deleted = false
                            AND rc.transferred_to_id = p_employee_id)
              OR EXISTS (SELECT 1 FROM qms.corrective_action cor
                          WHERE cor.complaint_id = c.complaint_id AND cor.is_deleted = false
                            AND cor.owner_id = p_employee_id)
              OR EXISTS (SELECT 1
                           FROM qms.action_verification av
                           JOIN qms.corrective_action cor2
                             ON cor2.corrective_action_id = av.corrective_action_id
                          WHERE cor2.complaint_id = c.complaint_id AND av.is_deleted = false
                            AND av.verified_by = p_employee_id)
              OR EXISTS (SELECT 1 FROM qms.report_8d rp
                          WHERE rp.complaint_id = c.complaint_id AND rp.is_deleted = false
                            AND rp.created_by = p_employee_id)
              OR EXISTS (SELECT 1 FROM qms.shipment sh
                          WHERE sh.complaint_id = c.complaint_id AND sh.is_deleted = false
                            AND (sh.sender_id = p_employee_id OR sh.receiver_id = p_employee_id))
           )
    );
$$;

COMMENT ON FUNCTION complaint_related(varchar, varchar) IS
    '台账/首页「与我相关」判定：主表 4 个责任人 + 发起人 + 各阶段任务负责人命中任一即为真。2026-10-14 业务确认口径。';
