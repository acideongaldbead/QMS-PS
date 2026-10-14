-- ===========================================================================
-- V10 物流状态字典（追加迁移）
-- ===========================================================================
-- shipment.shipment_status 在基线里是自由文本，既没有外键也没有字典。
-- 按 schema 自身的设计约定（「字典类字段在业务表只存 code，展示名取自字典表，
-- 不硬编码中文」），这里把状态码登记进 status_code 作为词条来源。
--
-- 刻意不建外键：基线的 shipment 表没有为此留约束，加外键会改变既有模型；
-- 本迁移只是让界面有统一的英文名可用。
-- ===========================================================================

SET search_path TO qms, public;

INSERT INTO status_code (status_code, entity_name, name_cn, name_en, sort_order, is_final) VALUES
    ('SHIPMENT_PREPARING',  'Shipment', '备货中', 'Preparing',  1, false),
    ('SHIPMENT_IN_TRANSIT', 'Shipment', '在途',   'In transit', 2, false),
    ('SHIPMENT_RECEIVED',   'Shipment', '已签收', 'Received',   3, true),
    ('SHIPMENT_CLOSED',     'Shipment', '已关闭', 'Closed',     4, true)
ON CONFLICT (status_code) DO UPDATE
    SET name_cn = EXCLUDED.name_cn, name_en = EXCLUDED.name_en;
