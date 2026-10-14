-- ===========================================================================
-- V9 主数据与组织人员（追加迁移）
-- ===========================================================================
-- 基线只种了 5 类主数据（complaint_type / priority / failure_location / file_type
-- / responsible_org）+ 三级失效类型的 4 个节点。但有 10 个外键指向
-- master_data_item(code)，其中 sub_segment / product_type / packing_type /
-- failure_mode 四类**完全缺失**；employee 表也是空的，而 complaint 的
-- complaint_owner_id 外键指向它 —— 不补上这些，一张投诉单都建不出来。
--
-- 取值来源：已验收的原型 docs/reference/mock-data.js 与需求文档示例，
-- 保持与原型口径一致。占位编码沿用基线的 <类型>_<序号> 规则。
--
-- 与 V10 的分工：本文件是「系统跑起来必须有的主数据」，生产环境保留；
-- V10 是可丢弃的演示业务数据。
-- ===========================================================================

SET search_path TO qms, public;

-- ---------------------------------------------------------------- 已有主数据补英文名
UPDATE master_data_item SET name_en = 'Technical complaint - complex'    WHERE code = 'COMPLAINT_TYPE_001';
UPDATE master_data_item SET name_en = 'Technical complaint - simple'     WHERE code = 'COMPLAINT_TYPE_002';
UPDATE master_data_item SET name_en = 'Logistics complaint'              WHERE code = 'COMPLAINT_TYPE_003';
UPDATE master_data_item SET name_en = 'Commercial complaint'             WHERE code = 'COMPLAINT_TYPE_004';
UPDATE master_data_item SET name_en = 'Analysis request'                 WHERE code = 'COMPLAINT_TYPE_005';
UPDATE master_data_item SET name_en = 'Internal complaint'               WHERE code = 'COMPLAINT_TYPE_006';
UPDATE master_data_item SET name_en = 'Standard'                         WHERE code = 'PRIORITY_001';
UPDATE master_data_item SET name_en = 'Urgent'                           WHERE code = 'PRIORITY_002';
UPDATE master_data_item SET name_en = 'Very urgent'                      WHERE code = 'PRIORITY_003';
UPDATE master_data_item SET name_en = 'Application test'                 WHERE code = 'FAILURE_LOCATION_001';
UPDATE master_data_item SET name_en = 'Production line rejection'        WHERE code = 'FAILURE_LOCATION_002';
UPDATE master_data_item SET name_en = 'Reliability monitoring'           WHERE code = 'FAILURE_LOCATION_003';
UPDATE master_data_item SET name_en = 'Update on Flow'                   WHERE code = 'FILE_TYPE_005';
UPDATE master_data_item SET name_en = 'Internal'                         WHERE code = 'RESPONSIBLE_ORG_001';
UPDATE master_data_item SET name_en = 'External root-cause organisation' WHERE code = 'RESPONSIBLE_ORG_002';

-- ---------------------------------------------------------------- 失效位置：补齐原型在用的取值
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('failure_location', 'FAILURE_LOCATION_004', '客户来料检验', 'Customer incoming inspection', 'QMS', 4, true),
    ('failure_location', 'FAILURE_LOCATION_005', '客户端装配',   'Customer assembly',            'QMS', 5, true),
    ('failure_location', 'FAILURE_LOCATION_006', '终端用户失效', 'End user failure',             'QMS', 6, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- 子分部（3.1.3 Sub Segment）
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('sub_segment', 'SUB_SEGMENT_001', '汽车 - 动力总成', 'Automotive - Powertrain', 'QMS', 1, true),
    ('sub_segment', 'SUB_SEGMENT_002', '汽车 - 车身',     'Automotive - Body',       'QMS', 2, true),
    ('sub_segment', 'SUB_SEGMENT_003', '汽车 - 底盘',     'Automotive - Chassis',    'QMS', 3, true),
    ('sub_segment', 'SUB_SEGMENT_004', '工业',            'Industrial',              'QMS', 4, true),
    ('sub_segment', 'SUB_SEGMENT_005', '消费类',           'Consumer',                'QMS', 5, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- 产品类型（3.1.4，文档未给取值）
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('product_type', 'PRODUCT_TYPE_001', 'MOSFET 功率器件', 'MOSFET power device',  'QMS', 1, true),
    ('product_type', 'PRODUCT_TYPE_002', '肖特基二极管',    'Schottky diode',       'QMS', 2, true),
    ('product_type', 'PRODUCT_TYPE_003', 'ESD 保护器件',    'ESD protection device','QMS', 3, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- 包装类型（3.1.4，文档未给取值）
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('packing_type', 'PACKING_TYPE_001', '卷带',   'Tape & Reel', 'QMS', 1, true),
    ('packing_type', 'PACKING_TYPE_002', '料管',   'Tube',        'QMS', 2, true),
    ('packing_type', 'PACKING_TYPE_003', '托盘',   'Tray',        'QMS', 3, true)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- 失效模式（3.1.5 Customer failure mode）
INSERT INTO master_data_item (md_type, code, name_cn, name_en, source_system, sort_order, is_active) VALUES
    ('failure_mode', 'FAILURE_MODE_001', '封装崩边',     'Package chipping',  'QMS', 1, true),
    ('failure_mode', 'FAILURE_MODE_002', '焊球脱落',     'Lifted ball bond',  'QMS', 2, true),
    ('failure_mode', 'FAILURE_MODE_003', '键合线断裂',   'Wire bond broken',  'QMS', 3, true),
    ('failure_mode', 'FAILURE_MODE_004', '芯片裂纹',     'Die crack',         'QMS', 4, true),
    ('failure_mode', 'FAILURE_MODE_005', '焊点空洞',     'Solder void',       'QMS', 5, true),
    ('failure_mode', 'FAILURE_MODE_006', '引脚变形',     'Lead bent',         'QMS', 6, true),
    ('failure_mode', 'FAILURE_MODE_007', '静电击穿',     'ESD damage',        'QMS', 7, true),
    ('failure_mode', 'FAILURE_MODE_008', '污染',         'Contamination',     'QMS', 8, true)
ON CONFLICT (code) DO NOTHING;

-- ===========================================================================
-- 失效类型三级主数据（3.3）
-- ===========================================================================
INSERT INTO failure_type (level_no, code, name, is_active) VALUES
    (1, '2', '2 - Assembly related',  true),
    (1, '3', '3 - Wafer related',     true),
    (1, '4', '4 - Test related',      true),
    (1, '5', '5 - Application related', true)
ON CONFLICT (code) DO NOTHING;

INSERT INTO failure_type (level_no, code, name, parent_id, is_active)
SELECT 2, v.code, v.name, p.failure_type_id, true
FROM (VALUES
    ('2a', '2a - Bond and wire', '2'),
    ('2b', '2b - Die attach',    '2'),
    ('2c', '2c - Molding',       '2'),
    ('3a', '3a - Front end',     '3'),
    ('3b', '3b - Back end',      '3'),
    ('4a', '4a - Electrical',    '4'),
    ('5a', '5a - Board level',   '5'),
    ('5b', '5b - Mechanical',    '5')
) AS v(code, name, parent_code)
JOIN failure_type p ON p.code = v.parent_code
ON CONFLICT (code) DO NOTHING;

INSERT INTO failure_type (level_no, code, name, parent_id, is_active)
SELECT 3, v.code, v.name, p.failure_type_id, true
FROM (VALUES
    ('2aa', '2aa - Lifted ball bond',        '2a'),
    ('2ab', '2ab - Wire broken / neck break','2a'),
    ('2ac', '2ac - Bond pad cratering',      '2a'),
    ('2ad', '2ad - Stitch bond lift',        '2a'),
    ('2ba', '2ba - Solder void',             '2b'),
    ('2bb', '2bb - Die tilt',                '2b'),
    ('2bc', '2bc - Delamination',            '2b'),
    ('2ca', '2ca - Package chipping',        '2c'),
    ('2cb', '2cb - Mold flash',              '2c'),
    ('2cc', '2cc - Void in mold',            '2c'),
    ('3aa', '3aa - Passivation defect',      '3a'),
    ('3ab', '3ab - Metal corrosion',         '3a'),
    ('3ac', '3ac - Poly void',               '3a'),
    ('3ba', '3ba - Backside chipping',       '3b'),
    ('3bb', '3bb - Wafer scratch',           '3b'),
    ('4aa', '4aa - Leakage current high',    '4a'),
    ('4ab', '4ab - Parametric out of spec',  '4a'),
    ('4ac', '4ac - Contact test failure',    '4a'),
    ('5aa', '5aa - Solder joint crack',      '5a'),
    ('5ab', '5ab - ESD damage',              '5a'),
    ('5ba', '5ba - Package crack',           '5b'),
    ('5bb', '5bb - Lead deformation',        '5b')
) AS v(code, name, parent_code)
JOIN failure_type p ON p.code = v.parent_code
ON CONFLICT (code) DO NOTHING;

-- ===========================================================================
-- 人员主数据（HR/MDM 同步源；一期还没有 HR 接口，先用这批数据）
-- ===========================================================================
INSERT INTO employee (employee_id, name, name_en, email, dept_l1, dept_l2, job_title, is_active) VALUES
    ('U01', '马晓然', 'Vivien Ma',    'xiaoran.ma@nexperia.com',   'Operations',    'Sales Quality',      '销售质量专员',   true),
    ('U02', '刘丹茜', 'Dancy Liu',    'dancy.liu@nexperia.com',    'Operations',    'Sales Quality',      '销售质量经理',   true),
    ('U03', '王振宇', 'Zhenyu Wang',  'zhenyu.wang@nexperia.com',  'Quality',       'Failure Analysis',   '失效分析工程师', true),
    ('U04', '李思远', 'Siyuan Li',    'siyuan.li@nexperia.com',    'Quality',       'Operations Quality', '质量工程师',     true),
    ('U05', '陈志远', 'Zhiyuan Chen', 'zhiyuan.chen@nexperia.com', 'Quality',       'BG Quality',         'BG 质量负责人',  true),
    ('U06', '赵敏',   'Min Zhao',     'min.zhao@nexperia.com',     'Manufacturing', 'Assembly',           '根因组织人员',   true),
    ('U07', '孙立',   'Li Sun',       'li.sun@nexperia.com',       'Manufacturing', 'Assembly',           'Assembly 负责人', true),
    ('U08', '周颖',   'Ying Zhou',    'ying.zhou@nexperia.com',    'IT',            'Platform',           '系统管理员',     true),
    ('U09', '张宏',   'Hong Zhang',   'hong.zhang@nexperia.com',   'Quality',       'Quality Management', '质量总监',       true)
ON CONFLICT (employee_id) DO NOTHING;

-- 直线经理（自关联，先插人再回填，避免顺序依赖）
UPDATE employee e SET line_manager_id = v.mgr FROM (VALUES
    ('U01', 'U02'), ('U02', 'U05'), ('U03', 'U05'), ('U04', 'U05'),
    ('U05', 'U09'), ('U06', 'U07'), ('U07', 'U09'), ('U08', 'U09')
) AS v(emp, mgr) WHERE e.employee_id = v.emp;

-- ===========================================================================
-- 登录账号
-- ===========================================================================
-- password_hash 写哨兵值 CHANGE_ME：应用在 local profile 启动时用 BCrypt 重算成
-- 交付说明里公布的口令。仓库里不留任何口令散列。
INSERT INTO user_account (employee_id, username, password_hash, is_active) VALUES
    ('U01', 'xiaoran.ma',   'CHANGE_ME', true),
    ('U02', 'dancy.liu',    'CHANGE_ME', true),
    ('U03', 'zhenyu.wang',  'CHANGE_ME', true),
    ('U04', 'siyuan.li',    'CHANGE_ME', true),
    ('U05', 'zhiyuan.chen', 'CHANGE_ME', true),
    ('U06', 'min.zhao',     'CHANGE_ME', true),
    ('U07', 'li.sun',       'CHANGE_ME', true),
    ('U08', 'ying.zhou',    'CHANGE_ME', true),
    ('U09', 'hong.zhang',   'CHANGE_ME', true)
ON CONFLICT (username) DO NOTHING;

-- ===========================================================================
-- 用户 × 角色（3.12 的四个预设角色）
-- ===========================================================================
INSERT INTO user_role (employee_id, role_id, effective_from)
SELECT v.emp, r.role_id, now() FROM (VALUES
    ('U01', 'ROLE_SALES_QUALITY'),
    ('U02', 'ROLE_SALES_QUALITY'),
    ('U03', 'ROLE_QUALITY_ENGINEER'),
    ('U04', 'ROLE_QUALITY_ENGINEER'),
    ('U06', 'ROLE_QUALITY_ENGINEER'),
    ('U07', 'ROLE_QUALITY_ENGINEER'),
    ('U05', 'ROLE_AUDITOR'),
    ('U09', 'ROLE_AUDITOR'),
    ('U08', 'ROLE_ADMINISTRATOR')
) AS v(emp, role_code)
JOIN role r ON r.role_code = v.role_code
ON CONFLICT (employee_id, role_id) DO NOTHING;

-- ===========================================================================
-- 客户主数据（SAP）
-- ===========================================================================
INSERT INTO customer (customer_code, customer_name, country, city, street_address, synced_at) VALUES
    ('CUST-1001', '博世汽车部件（苏州）有限公司',   '中国', '苏州', '苏州工业园区苏虹西路 128 号',        now()),
    ('CUST-1002', '大陆汽车电子（芜湖）有限公司',   '中国', '芜湖', '芜湖市鸠江区长江北路 55 号',          now()),
    ('CUST-1003', '深圳华为技术有限公司',           '中国', '深圳', '深圳市龙岗区坂田华为基地',            now()),
    ('CUST-1004', '采埃孚（中国）投资有限公司',     '中国', '上海', '上海市嘉定区安亭镇墨玉南路 888 号',   now())
ON CONFLICT (customer_code) DO NOTHING;

INSERT INTO contact_person (contact_id, customer_code, contact_name, email, source_type) VALUES
    ('CP-1001', 'CUST-1001', '张伟 / Wei Zhang', 'wei.zhang@bosch.com',          '主数据同步'),
    ('CP-1002', 'CUST-1002', '李娜 / Na Li',     'na.li@continental.com',        '主数据同步'),
    ('CP-1003', 'CUST-1003', '王强 / Qiang Wang','qiang.wang@huawei.com',        '主数据同步'),
    ('CP-1004', 'CUST-1004', '陈静 / Jing Chen', 'jing.chen@zf.com',             '主数据同步')
ON CONFLICT (contact_id) DO NOTHING;

INSERT INTO ship_to_sold_to (ship_to_code, customer_code, ship_to_name, ship_to_type, synced_at) VALUES
    ('ST-1001-01', 'CUST-1001', '通用武汉工厂',       'Ship-To', now()),
    ('ST-1001-02', 'CUST-1001', '通用烟台工厂',       'Ship-To', now()),
    ('ST-1002-01', 'CUST-1002', '大陆芜湖总装厂',     'Ship-To', now()),
    ('ST-1002-02', 'CUST-1002', '大众佛山工厂',       'Ship-To', now()),
    ('ST-1003-01', 'CUST-1003', '华为东莞松山湖工厂', 'Ship-To', now()),
    ('ST-1004-01', 'CUST-1004', '采埃孚上海工厂',     'Ship-To', now())
ON CONFLICT (ship_to_code) DO NOTHING;

-- ===========================================================================
-- 产品主数据（PLM/SAP）
-- ===========================================================================
INSERT INTO product_master (material_code, description, product_type_code, business_group, business_unit, packing_type_code, synced_at) VALUES
    ('12NC-934068123456', 'MOSFET 功率器件 · TO-252 (DPAK) · Trench MOS 0.35 µm', 'PRODUCT_TYPE_001', 'Power Discretes', 'Automotive Power', 'PACKING_TYPE_001', now()),
    ('12NC-934068789012', '肖特基二极管 · SOD123 · Planar 0.5 µm',                 'PRODUCT_TYPE_002', 'Power Discretes', 'Automotive Power', 'PACKING_TYPE_001', now()),
    ('12NC-934071234567', 'ESD 保护器件 · SOD323 · Planar 0.5 µm',                 'PRODUCT_TYPE_003', 'Protection',      'Automotive Power', 'PACKING_TYPE_002', now())
ON CONFLICT (material_code) DO NOTHING;

-- ===========================================================================
-- 生产主数据（MES：工序组 / 工序 / 生产线机台）
-- ===========================================================================
INSERT INTO production_master (pm_id, pm_type, code, name, parent_id, synced_at) VALUES
    ('PG-01', '工序组', 'PG-01', 'Assembly',        NULL, now()),
    ('PG-02', '工序组', 'PG-02', 'Front End',       NULL, now()),
    ('PG-03', '工序组', 'PG-03', 'Final Test',      NULL, now())
ON CONFLICT (pm_id) DO NOTHING;

INSERT INTO production_master (pm_id, pm_type, code, name, parent_id, synced_at) VALUES
    ('PR-01', '工序', 'PR-01', 'Die Attach',    'PG-01', now()),
    ('PR-02', '工序', 'PR-02', 'Wire Bond',     'PG-01', now()),
    ('PR-03', '工序', 'PR-03', 'Molding',       'PG-01', now()),
    ('PR-04', '工序', 'PR-04', 'Trim and Form', 'PG-01', now())
ON CONFLICT (pm_id) DO NOTHING;

INSERT INTO production_master (pm_id, pm_type, code, name, parent_id, synced_at) VALUES
    ('MC-01', '生产线机台', 'MC-01', 'Bonder #1', 'PR-02', now()),
    ('MC-02', '生产线机台', 'MC-02', 'Bonder #2', 'PR-02', now()),
    ('MC-03', '生产线机台', 'MC-03', 'Molder #3', 'PR-03', now())
ON CONFLICT (pm_id) DO NOTHING;

-- ===========================================================================
-- 通知规则 / TPT 目标（3.13）
-- ===========================================================================
-- 口径说明：需求正文提到「样品登记后 5 个工作日提醒完成 FA」、报表样例含
-- Target(3D)=3 天 与 Target(8D)=6 天；这三条在原型与需求间尚未完全对齐，
-- 先按此落库，界面上标注「口径待业务方确认」。
INSERT INTO notification_rule (milestone_code, target_days, priority_scope, remind_before_days, escalate_to_id, is_active) VALUES
    ('FA',     5, NULL, 1, 'U02', true),
    ('TPT-3D', 3, NULL, 1, 'U02', true),
    ('TPT-8D', 6, NULL, 2, 'U05', true)
ON CONFLICT DO NOTHING;

-- ===========================================================================
-- 系统公告（首页工作台）
-- ===========================================================================
INSERT INTO system_announcement (title, content, publish_status, published_by, published_at) VALUES
    ('QMS 问题解决管理系统上线', 'QMS 问题解决管理系统一期开始试运行。本期覆盖客户投诉登记、样品物流、D2 验证、D3-D7 措施跟踪与 8D 报告编制发送的完整闭环。使用中如遇问题请联系 IT 平台组。', '已发布', 'U08', now()),
    ('8D 报告模板统一为 XTE-0071', '8D 报告正式模板已确认为 XTE-0071 8D Problem Report，系统内自动生成的报告将统一使用该模板。章节结构：D1 跨职能团队 / D2 问题描述 / D3 遏制措施 / D4 根本原因 / D5 备选纠正措施 / D6 已实施纠正措施 / D7 系统性纠正措施 / D8 签署与分发。', '已发布', 'U08', now()),
    ('一期不包含的功能', '飞书通知与移动端审批、经验分享与标签检索、AI 生成 3x5Why 与鱼骨图、FMEA 模块本体、SAP/PLM/HR/MES 主数据自动同步均安排在二期。一期相关主数据由管理员在系统内手工维护。', '已发布', 'U08', now())
ON CONFLICT DO NOTHING;
