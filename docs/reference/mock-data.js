/* ==========================================================================
   QMS 原型 · Mock 数据
   --------------------------------------------------------------------------
   字段与业务规则严格对齐《QMS-问题解决管理系统采购需求 V8》与一期 Backlog：
   · 投诉ID 规则 C+4位年+5位序号（C202600722）
   · 开始日期 = 创建日期 + 7 天
   · 目标日期 = 开始日期 + 优先级天数（非常紧急 7 / 紧急 10 / 标准 14）
   · 8D 阶段 D0-D8，台账双页签「与我相关 / 全部数据」
   演示基准日：2026-09-24
   ========================================================================== */

window.QMS = (function () {
  'use strict';

  var TODAY = '2026-09-24';

  /* ---------------- 人员与角色 ---------------- */

  var users = {
    U01: { id: 'U01', name: '马晓然', en: 'Vivien Ma',   email: 'xiaoran.ma@nexperia.com', dept1: 'Operations', dept2: 'Sales Quality',      manager: '刘丹茜', title: '销售质量专员' },
    U02: { id: 'U02', name: '刘丹茜', en: 'Dancy Liu',   email: 'dancy.liu@nexperia.com',  dept1: 'Operations', dept2: 'Sales Quality',      manager: '陈志远', title: '销售质量经理' },
    U03: { id: 'U03', name: '王振宇', en: 'Zhenyu Wang', email: 'zhenyu.wang@nexperia.com', dept1: 'Quality',   dept2: 'Failure Analysis',   manager: '陈志远', title: '失效分析工程师' },
    U04: { id: 'U04', name: '李思远', en: 'Siyuan Li',   email: 'siyuan.li@nexperia.com',  dept1: 'Quality',    dept2: 'Operations Quality', manager: '陈志远', title: '质量工程师' },
    U05: { id: 'U05', name: '陈志远', en: 'Zhiyuan Chen', email: 'zhiyuan.chen@nexperia.com', dept1: 'Quality', dept2: 'BG Quality',          manager: '张宏',   title: 'BG 质量负责人' },
    U06: { id: 'U06', name: '赵敏',   en: 'Min Zhao',    email: 'min.zhao@nexperia.com',   dept1: 'Manufacturing', dept2: 'Assembly',        manager: '孙立',   title: '根因组织人员' },
    U07: { id: 'U07', name: '孙立',   en: 'Li Sun',      email: 'li.sun@nexperia.com',     dept1: 'Manufacturing', dept2: 'Assembly',        manager: '张宏',   title: 'Assembly 负责人' },
    U08: { id: 'U08', name: '周颖',   en: 'Ying Zhou',   email: 'ying.zhou@nexperia.com',  dept1: 'IT',         dept2: 'Platform',            manager: '张宏',   title: '系统管理员' },
    U09: { id: 'U09', name: '张宏',   en: 'Hong Zhang',  email: 'hong.zhang@nexperia.com', dept1: 'Quality',    dept2: 'Quality Management',  manager: '—',      title: '质量总监' }
  };

  /* 一期预设标准角色（以需求 3.12 四个标准角色为基座，不增补 RACI 根因组织角色） */
  var roles = [
    { id: 'R1', name: '销售质量专员', en: 'Sales Quality',   users: ['U01', 'U02'], desc: '登记投诉、发送报告（对外唯一出口）' },
    { id: 'R2', name: '质量工程师',   en: 'Quality Engineer', users: ['U04', 'U06'], desc: '样品物流登记、验证任务、措施推进' },
    { id: 'R3', name: '审核员',       en: 'Auditor',          users: ['U05'],        desc: '只读查看全量数据与审计日志' },
    { id: 'R4', name: '管理员',       en: 'Administrator',    users: ['U08'],        desc: '主数据、权限、配置维护' }
  ];

  /* 原型顶栏角色切换器：演示同一单据的不同视角。默认角色 = 质量工程师（用户口中的主要使用者） */
  var personas = [
    { key: 'qe',     name: '质量工程师',   user: 'U04', hint: '样品物流 · 措施跟踪 · 根因分析' },
    { key: 'sales',  name: '销售质量专员', user: 'U01', hint: '登记投诉 · 发送报告' },
    { key: 'fa',     name: '失效分析工程师', user: 'U03', hint: '验证任务 · 结果录入' },
    { key: 'owner',  name: '投诉负责人',   user: 'U02', hint: '流程推进 · 遏制措施' },
    { key: 'appr',   name: '审批人',       user: 'U05', hint: '8D 报告审批' },
    { key: 'mgr',    name: '质量管理者',   user: 'U09', hint: '报表与 KPI' },
    { key: 'admin',  name: '系统管理员',   user: 'U08', hint: '主数据 · 权限 · 集成' }
  ];

  /* ---------------- 主数据 ---------------- */

  var md = {
    complaintType: ['技术投诉 - 复杂', '技术投诉 - 非复杂', '物流投诉', '商务投诉', '分析申请', '内部投诉'],
    priority: [
      { code: 'P1', name: '非常紧急', days: 7 },
      { code: 'P2', name: '紧急',     days: 10 },
      { code: 'P3', name: '标准',     days: 14 }
    ],
    failureLocation: ['应用测试', '产线拒收', '可靠性监控', '客户来料检验', '客户端装配', '终端用户失效'],
    failureMode: ['Package chipping', 'Lifted ball bond', 'Wire bond broken', 'Die crack', 'Solder void', 'Lead bent', 'ESD damage', 'Contamination'],
    subSegment: ['Automotive - Powertrain', 'Automotive - Body', 'Automotive - Chassis', 'Industrial', 'Consumer']
  };

  /* Failure Type 三级（样例取自需求文档内嵌电子表格） */
  var failureTypes = [
    { l1: '2 - Assembly related', children: [
      { l2: '2a - Bond and wire', children: [
        { l3: '2aa - Lifted ball bond' },
        { l3: '2ab - Wire broken / neck break' },
        { l3: '2ac - Bond pad cratering' },
        { l3: '2ad - Stitch bond lift' }
      ]},
      { l2: '2b - Die attach', children: [
        { l3: '2ba - Solder void' },
        { l3: '2bb - Die tilt' },
        { l3: '2bc - Delamination' }
      ]},
      { l2: '2c - Molding', children: [
        { l3: '2ca - Package chipping' },
        { l3: '2cb - Mold flash' },
        { l3: '2cc - Void in mold' }
      ]}
    ]},
    { l1: '3 - Wafer related', children: [
      { l2: '3a - Front end', children: [
        { l3: '3aa - Passivation defect' },
        { l3: '3ab - Metal corrosion' },
        { l3: '3ac - Poly void' }
      ]},
      { l2: '3b - Back end', children: [
        { l3: '3ba - Backside chipping' },
        { l3: '3bb - Wafer scratch' }
      ]}
    ]},
    { l1: '4 - Test related', children: [
      { l2: '4a - Electrical', children: [
        { l3: '4aa - Leakage current high' },
        { l3: '4ab - Parametric out of spec' },
        { l3: '4ac - Contact test failure' }
      ]}
    ]},
    { l1: '5 - Application related', children: [
      { l2: '5a - Board level', children: [
        { l3: '5aa - Solder joint crack' },
        { l3: '5ab - ESD damage' }
      ]},
      { l2: '5b - Mechanical', children: [
        { l3: '5ba - Package crack' },
        { l3: '5bb - Lead deformation' }
      ]}
    ]}
  ];

  /* 客户主数据（来自 SAP） */
  var customers = [
    { code: 'CUST-1001', name: '博世汽车部件（苏州）有限公司', country: '中国', city: '苏州', street: '苏州工业园区苏虹西路 128 号', contact: '张伟 / Wei Zhang', subSegment: 'Automotive - Powertrain', shipTo: ['通用武汉工厂', '通用烟台工厂', '深圳华为'] },
    { code: 'CUST-1002', name: '大陆汽车电子（芜湖）有限公司', country: '中国', city: '芜湖', street: '芜湖市鸠江区长江北路 55 号', contact: '李娜 / Na Li', subSegment: 'Automotive - Body', shipTo: ['大陆芜湖总装厂', '大众佛山工厂'] },
    { code: 'CUST-1003', name: '深圳华为技术有限公司', country: '中国', city: '深圳', street: '深圳市龙岗区坂田华为基地', contact: '王强 / Qiang Wang', subSegment: 'Industrial', shipTo: ['华为东莞松山湖工厂'] },
    { code: 'CUST-1004', name: '采埃孚（中国）投资有限公司', country: '中国', city: '上海', street: '上海市嘉定区安亭镇墨玉南路 888 号', contact: '陈静 / Jing Chen', subSegment: 'Automotive - Chassis', shipTo: ['采埃孚上海工厂'] }
  ];

  /* 产品主数据（来自 PLM/SAP）
     pkg / diffusion 两个字段来自真实 8D 报告表头（Package / Diffusion Process） */
  var products = [
    { code: '12NC-934068123456', type: 'MOSFET 功率器件', group: 'Power Discretes', bu: 'Automotive Power', packing: 'Tape & Reel', pkg: 'TO-252 (DPAK)', diffusion: 'Trench MOS 0.35 µm', mag: 'MAG-A', customerPartNo: 'BOS-8812-A', p4tg: '4TG-11', p5gt: '5GT-02', p6gt: '6GT-07', status: 'Active' },
    { code: '12NC-934068789012', type: '肖特基二极管', group: 'Power Discretes', bu: 'Automotive Power', packing: 'Tape & Reel', pkg: 'SOD123', diffusion: 'Planar 0.5 µm', mag: 'MAG-B', customerPartNo: 'CON-2201-C', p4tg: '4TG-14', p5gt: '5GT-05', p6gt: '6GT-02', status: 'Active' },
    { code: '12NC-934071234567', type: 'ESD 保护器件', group: 'Protection', bu: 'Automotive Power', packing: 'Tube', pkg: 'SOD323', diffusion: 'Planar 0.5 µm', mag: 'MAG-A', customerPartNo: 'HUA-3390-H', p4tg: '4TG-02', p5gt: '5GT-09', p6gt: '6GT-01', status: 'Active' }
  ];

  /* ---------------- 投诉主表：8 条手写样例 ---------------- */

  var heroComplaints = [
    {
      id: 'C202600722', status: '分析-进行中', stage: 'D4', flowType: '客诉 - 技术投诉',
      priority: 'P1', priorityName: '非常紧急',
      complaintType: '技术投诉 - 复杂', failureLocation: '客户端装配',
      initiator: 'U01', createdAt: '2026-09-08 09:24',
      complaintOwner: 'U02', coordinator: 'U01', verifier: 'U03', reportOwner: 'U01',
      startDate: '2026-09-15', targetDate: '2026-09-22', customerTargetDate: '2026-09-28',
      closeDate: null, valid: null, days: 16, minDay: null,
      customer: 'CUST-1001', shipTo: '通用武汉工厂', application: 'Yes',
      contact: '张伟 / Wei Zhang', hsCode: '8541.29.00', endCustomer: '通用汽车', eccn: 'EAR99',
      product: '12NC-934068123456', quantityFailing: 120, uom: 'PCS', quantityReturned: 8,
      customerRefId: 'GM-WH-SC-2026-0913', customerPo: 'PO-4500982113', salesOrder: 'SO-2026088', supplierInvoice: 'INV-2026-1187',
      shippedDirectly: 'No', directComm: 'Yes', receivedApprPack: 'Yes',
      failureMode: 'Package chipping',
      symptoms: '客户在通用武汉工厂进行装配前的来料检验时，发现 120 pcs 器件本体出现封装崩边。崩边位于塑封体顶面靠近引脚一侧，长度约 0.3–0.5 mm，肉眼可见。客户怀疑为包装容器变形导致在运输/拆包过程中产生机械应力。',
      conclusion: 'Package chipping was found on returned sample. This chipping is caused when deformed container is unscrewed.',
      comment: '客户已暂停该批次上线，要求 3 个工作日内给出遏制措施。'
    },
    {
      id: 'C202600718', status: '报告-待审批', stage: 'D8', flowType: '客诉 - 技术投诉',
      priority: 'P2', priorityName: '紧急',
      complaintType: '技术投诉 - 非复杂', failureLocation: '产线拒收',
      initiator: 'U01', createdAt: '2026-09-02 14:10',
      complaintOwner: 'U02', coordinator: 'U01', verifier: 'U03', reportOwner: 'U01',
      startDate: '2026-09-09', targetDate: '2026-09-19', customerTargetDate: '2026-09-25',
      closeDate: null, valid: 'Yes', days: 22, minDay: null,
      customer: 'CUST-1002', shipTo: '大陆芜湖总装厂', application: 'Yes',
      contact: '李娜 / Na Li', hsCode: '8541.10.00', endCustomer: '大众汽车', eccn: 'EAR99',
      product: '12NC-934068789012', quantityFailing: 340, uom: 'PCS', quantityReturned: 12,
      customerRefId: 'CON-WH-2026-0821', customerPo: 'PO-4500977554', salesOrder: 'SO-2026071', supplierInvoice: 'INV-2026-1102',
      shippedDirectly: 'No', directComm: 'No', receivedApprPack: 'Yes',
      failureMode: 'Solder void',
      symptoms: '客户回流焊后 X-Ray 检查发现焊点空洞率超标，抽样 12 颗中 5 颗空洞率超过 25%，超出客户 15% 的接受标准，触发产线拒收。',
      conclusion: 'Excessive solder void confirmed on 5 of 12 samples. Void rate 26%–34%, exceeding customer limit of 15%.',
      comment: '根因已定位为封装内部离层导致的热阻异常，纠正措施已完成验证，待 BG 质量审批。'
    },
    {
      id: 'C202600735', status: '验证-进行中', stage: 'D2', flowType: '客诉 - 技术投诉',
      priority: 'P2', priorityName: '紧急',
      complaintType: '技术投诉 - 非复杂', failureLocation: '客户来料检验',
      initiator: 'U01', createdAt: '2026-09-15 10:32',
      complaintOwner: 'U02', coordinator: 'U04', verifier: 'U03', reportOwner: 'U01',
      startDate: '2026-09-22', targetDate: '2026-10-02', customerTargetDate: '2026-10-08',
      closeDate: null, valid: null, days: 9, minDay: 2,
      customer: 'CUST-1003', shipTo: '华为东莞松山湖工厂', application: 'Yes',
      contact: '王强 / Qiang Wang', hsCode: '8536.30.00', endCustomer: '华为', eccn: 'EAR99',
      product: '12NC-934071234567', quantityFailing: 45, uom: 'PCS', quantityReturned: 6,
      customerRefId: 'HUA-SZ-2026-0905', customerPo: 'PO-4500990012', salesOrder: 'SO-2026103', supplierInvoice: 'INV-2026-1240',
      shippedDirectly: 'Yes', directComm: 'Yes', receivedApprPack: 'Yes',
      failureMode: 'ESD damage',
      symptoms: '客户产线反馈 ESD 保护器件在整机 ESD 测试（IEC 61000-4-2 接触放电 8kV）中失效，失效器件呈短路状态。',
      conclusion: '',
      comment: '样品已于 9/22 送达失效分析工位，验证任务排期完成。'
    },
    {
      id: 'C202600741', status: '登记-已启动', stage: 'D0',
      flowType: '客诉 - 物流投诉',
      priority: 'P3', priorityName: '标准',
      complaintType: '物流投诉', failureLocation: '应用测试',
      initiator: 'U01', createdAt: '2026-09-23 16:48',
      complaintOwner: 'U01', coordinator: 'U02', verifier: null, reportOwner: null,
      startDate: '2026-09-30', targetDate: '2026-10-14', customerTargetDate: '2026-10-20',
      closeDate: null, valid: null, days: 1, minDay: null,
      customer: 'CUST-1004', shipTo: '采埃孚上海工厂', application: 'No',
      contact: '陈静 / Jing Chen', hsCode: '8541.29.00', endCustomer: '采埃孚', eccn: 'EAR99',
      product: '12NC-934068123456', quantityFailing: 0, uom: 'PCS', quantityReturned: 0,
      customerRefId: 'ZF-SH-2026-0919', customerPo: 'PO-4500991330', salesOrder: '', supplierInvoice: '',
      shippedDirectly: 'No', directComm: 'No', receivedApprPack: 'No',
      failureMode: '',
      symptoms: '客户反馈货物到达时外箱有明显挤压变形，内包装完好但要求记录并追溯。',
      conclusion: '',
      comment: '尚未确定是否需要寄回样品。'
    },
    {
      id: 'C202600703', status: '措施-验证中', stage: 'D6', flowType: '客诉 - 技术投诉',
      priority: 'P2', priorityName: '紧急',
      complaintType: '技术投诉 - 复杂', failureLocation: '可靠性监控',
      initiator: 'U04', createdAt: '2026-08-18 11:05',
      complaintOwner: 'U04', coordinator: 'U02', verifier: 'U03', reportOwner: 'U04',
      startDate: '2026-08-25', targetDate: '2026-09-04', customerTargetDate: '2026-09-10',
      closeDate: null, valid: 'Yes', days: 37, minDay: null,
      customer: 'CUST-1001', shipTo: '通用烟台工厂', application: 'Yes',
      contact: '张伟 / Wei Zhang', hsCode: '8541.29.00', endCustomer: '通用汽车', eccn: 'EAR99',
      product: '12NC-934068123456', quantityFailing: 18, uom: 'PCS', quantityReturned: 18,
      customerRefId: 'GM-YT-2026-0805', customerPo: 'PO-4500968812', salesOrder: 'SO-2026044', supplierInvoice: 'INV-2026-0913',
      shippedDirectly: 'No', directComm: 'No', receivedApprPack: 'Yes',
      failureMode: 'Lifted ball bond',
      symptoms: '可靠性监控（HTRB 1000h）中 18 颗样品出现漏电超标，开封分析显示键合球脱离。',
      conclusion: 'Lifted ball bond confirmed. Root cause traced to bond pad contamination from upstream cleaning process.',
      comment: '纠正措施已实施，正在等待 1000h 验证数据回收。'
    },
    {
      id: 'C202600690', status: '结案-已关闭', stage: 'D8', flowType: '客诉 - 技术投诉',
      priority: 'P3', priorityName: '标准',
      complaintType: '技术投诉 - 非复杂', failureLocation: '应用测试',
      initiator: 'U01', createdAt: '2026-07-20 09:15',
      complaintOwner: 'U02', coordinator: 'U01', verifier: 'U03', reportOwner: 'U01',
      startDate: '2026-07-27', targetDate: '2026-08-10', customerTargetDate: '2026-08-15',
      closeDate: '2026-08-12', valid: 'Yes', days: 23, minDay: 23,
      customer: 'CUST-1002', shipTo: '大众佛山工厂', application: 'Yes',
      contact: '李娜 / Na Li', hsCode: '8541.10.00', endCustomer: '大众汽车', eccn: 'EAR99',
      product: '12NC-934068789012', quantityFailing: 9, uom: 'PCS', quantityReturned: 9,
      customerRefId: 'CON-FS-2026-0708', customerPo: 'PO-4500955321', salesOrder: 'SO-2026019', supplierInvoice: 'INV-2026-0742',
      shippedDirectly: 'No', directComm: 'No', receivedApprPack: 'Yes',
      failureMode: 'Wire bond broken',
      symptoms: '客户反馈在温度循环测试后出现开路失效。',
      conclusion: 'Wire bond neck break confirmed, caused by excessive capillary wear. Capillary replacement interval updated.',
      comment: '8D 报告已发送客户确认，投诉已结案。'
    },
    {
      id: 'C202600745', status: '验证-进行中', stage: 'D2', flowType: '客诉 - 技术投诉',
      priority: 'P2', priorityName: '紧急',
      complaintType: '分析申请', failureLocation: '终端用户失效',
      initiator: 'U01', createdAt: '2026-09-18 15:22',
      complaintOwner: 'U02', coordinator: 'U04', verifier: 'U03', reportOwner: 'U01',
      startDate: '2026-09-25', targetDate: '2026-10-05', customerTargetDate: '2026-10-05',
      closeDate: null, valid: null, days: 6, minDay: null,
      customer: 'CUST-1003', shipTo: '华为东莞松山湖工厂', application: 'Yes',
      contact: '王强 / Qiang Wang', hsCode: '8536.30.00', endCustomer: '华为', eccn: 'EAR99',
      product: '12NC-934071234567', quantityFailing: 3, uom: 'PCS', quantityReturned: 3,
      customerRefId: 'HUA-SZ-2026-0914', customerPo: 'PO-4500991112', salesOrder: '', supplierInvoice: '',
      shippedDirectly: 'No', directComm: 'Yes', receivedApprPack: 'No',
      failureMode: 'Contamination',
      symptoms: '客户端整机返修时发现器件表面有异常附着物，怀疑为污染导致，申请分析确认责任归属。',
      conclusion: '',
      comment: '客户申请确认失效是否由我方造成，初步判断可能为客户侧工艺残留。'
    },
    {
      id: 'C202600729', status: '遏制-进行中', stage: 'D3', flowType: '客诉 - 内部质量问题',
      priority: 'P1', priorityName: '非常紧急',
      complaintType: '内部投诉', failureLocation: '产线拒收',
      initiator: 'U04', createdAt: '2026-09-11 08:40',
      complaintOwner: 'U04', coordinator: 'U02', verifier: 'U03', reportOwner: 'U04',
      startDate: '2026-09-18', targetDate: '2026-09-25', customerTargetDate: '2026-09-30',
      closeDate: null, valid: 'Yes', days: 13, minDay: 5,
      customer: 'CUST-1001', shipTo: '通用武汉工厂', application: 'No',
      contact: '张伟 / Wei Zhang', hsCode: '8541.29.00', endCustomer: '通用汽车', eccn: 'EAR99',
      product: '12NC-934068123456', quantityFailing: 260, uom: 'PCS', quantityReturned: 0,
      customerRefId: 'INT-WH-2026-0902', customerPo: '', salesOrder: '', supplierInvoice: '',
      shippedDirectly: 'No', directComm: 'No', receivedApprPack: 'No',
      failureMode: 'Lead bent',
      symptoms: '内部产线 AOI 检出 260 pcs 引脚变形，判定为内部质量问题（非客诉），已隔离同批次在制品。',
      conclusion: '',
      comment: '无需客户寄回样品，遏制措施正在执行。'
    }
  ];

  /* ---------------- 投诉主表：生成的补充记录 ---------------- */
  /* 目的：让台账具备真实数据量，分页 / 排序 / 筛选 / 双页签才有演示意义。
     日期由「阶段 + 未结案/已结案」反推，使超期分布符合真实漏斗形态。 */

  var FAILURE_TEXT = {
    'Package chipping': { sym: '客户在来料检验时发现器件塑封体顶面出现崩边，长度约 0.3–0.5 mm，肉眼可见。', concl: 'Package chipping confirmed on returned samples. Mechanical stress during handling or transport suspected.' },
    'Lifted ball bond': { sym: '可靠性测试后出现漏电超标，开封分析显示键合球与焊盘脱离。', concl: 'Lifted ball bond confirmed by decapsulation. Bond pad contamination traced to upstream cleaning process.' },
    'Wire bond broken': { sym: '温度循环测试后出现开路失效，开封可见键合线颈部断裂。', concl: 'Wire bond neck break confirmed. Capillary wear exceeded the replacement limit.' },
    'Die crack': { sym: '客户整机测试中出现参数漂移，X-Ray 与断面分析发现芯片裂纹。', concl: 'Die crack confirmed, originating from backside grinding damage.' },
    'Solder void': { sym: '客户回流焊后 X-Ray 检查发现焊点空洞率超标，超出客户接受标准。', concl: 'Excessive solder void confirmed. Void rate above the customer limit of 15%.' },
    'Lead bent': { sym: '产线 AOI 检出引脚变形，无法正常贴装。', concl: 'Lead deformation confirmed. Caused by tray handling during final packing.' },
    'ESD damage': { sym: '整机 ESD 测试后器件失效，实测呈短路状态。', concl: 'ESD damage confirmed at pin 3. ESD protection diode junction burned.' },
    'Contamination': { sym: '客户返修时发现器件表面存在异常附着物。', concl: 'Foreign material identified as flux residue by EDS analysis; origin under evaluation.' }
  };

  var END_CUSTOMER = { 'CUST-1001': '通用汽车', 'CUST-1002': '大众汽车', 'CUST-1003': '华为', 'CUST-1004': '采埃孚' };

  /* 状态采用「阶段-子状态」两段式，与需求 3.1.2 的示例口径（登记-已启动 / 验证-已排期）一致 */
  var STAGE_STATUS = {
    D0: '登记-已启动', D1: '登记-已启动', D2: '验证-已排期', D3: '遏制-进行中',
    D4: '分析-进行中', D5: '措施-制定中', D6: '措施-验证中', D7: '预防-文件更新中', D8: '报告-待审批'
  };

  var STAGE_ORDER_ALL = ['D0', 'D1', 'D2', 'D3', 'D4', 'D5', 'D6', 'D7', 'D8'];
  var GEN_STAGES = ['D0', 'D2', 'D2', 'D3', 'D4', 'D4', 'D5', 'D6', 'D7', 'D8'];
  var GEN_PRIOS = ['P3', 'P3', 'P2', 'P3', 'P2', 'P3', 'P1', 'P2'];
  /* 责任人池刻意不含 U01（马晓然），否则「与我相关」会接近「全部数据」，
     双页签就演示不出差异。U01 仅以「报告负责人」身份出现在 1/3 的单据上。 */
  var GEN_POOL = ['U02', 'U04', 'U05', 'U07', 'U06'];
  var GEN_VERIFS = ['U03', 'U03', null, 'U03'];
  var GEN_HS = ['8541.29.00', '8541.10.00', '8536.30.00', '8541.40.00'];
  var GEN_QTY = [8, 12, 24, 45, 60, 120, 260, 340];
  var GEN_RET = [2, 4, 6, 9, 12, 18];

  function addDaysISO(baseISO, n) {
    var d = new Date(baseISO + 'T00:00:00');
    d.setDate(d.getDate() + n);
    return d.toISOString().slice(0, 10);
  }
  function pick(arr, i) { return arr[i % arr.length]; }

  var generatedComplaints = [];

  for (var gi = 0; gi < 40; gi++) {
    var gStage = pick(GEN_STAGES, gi);
    var gPrio = pick(GEN_PRIOS, gi);
    var gCust = pick(customers, gi);
    var gProd = pick(products, gi + 1);
    var gFm = pick(md.failureMode, gi + 2);
    var gStageIdx = STAGE_ORDER_ALL.indexOf(gStage);
    var gClosed = (gStage === 'D8') && (gi % 2 === 0);

    /* 阶段越靠后不代表一定超期——推进快的单子仍在目标期内。用较缓的年龄递增，
       让超期率落在 20% 左右（真实 TPT 形态），而不是「过了 D3 就一定超期」。 */
    var ageDays = gClosed ? (75 + (gi % 40)) : (3 + Math.round(gStageIdx * 2.2) + (gi % 3));
    var gCreated = addDaysISO(TODAY, -ageDays);
    var gStart = addDaysISO(gCreated, 7);
    var gTarget = addDaysISO(gStart, priorityInfo(gPrio).days);
    var gClose = gClosed ? addDaysISO(gTarget, (gi % 5) + 1) : null;

    var ft = FAILURE_TEXT[gFm] || { sym: '客户反馈器件功能异常，申请分析确认。', concl: 'Under analysis.' };

    generatedComplaints.push({
      id: 'C2026' + pad(601 + gi, 5),
      status: gClosed ? '结案-已关闭' : STAGE_STATUS[gStage],
      stage: gStage,
      flowType: (gi % 11 === 0) ? '客诉 - 内部质量问题' : '客诉 - 技术投诉',
      priority: gPrio,
      priorityName: priorityInfo(gPrio).name,
      complaintType: (gi % 11 === 0) ? '内部投诉' : '技术投诉 - 非复杂',
      failureLocation: pick(md.failureLocation, gi),
      initiator: (gi % 3 === 0) ? 'U01' : 'U04',
      createdAt: gCreated + ' ' + pad(8 + (gi % 9), 2) + ':' + pad((gi * 7) % 60, 2),
      complaintOwner: pick(GEN_POOL, gi),
      coordinator: pick(GEN_POOL, gi + 2),
      verifier: pick(GEN_VERIFS, gi),
      reportOwner: (gi % 3 === 0) ? 'U01' : pick(GEN_POOL, gi + 1),
      startDate: gStart,
      targetDate: gTarget,
      customerTargetDate: addDaysISO(gTarget, -(3 + (gi % 8))),
      closeDate: gClose,
      valid: gStageIdx >= 3 ? 'Yes' : null,
      days: 0,
      minDay: null,
      customer: gCust.code,
      shipTo: pick(gCust.shipTo, gi),
      application: (gi % 7 === 0) ? 'No' : 'Yes',
      contact: gCust.contact,
      hsCode: pick(GEN_HS, gi),
      endCustomer: END_CUSTOMER[gCust.code],
      eccn: 'EAR99',
      product: gProd.code,
      quantityFailing: pick(GEN_QTY, gi),
      uom: 'PCS',
      quantityReturned: Math.min(pick(GEN_QTY, gi), pick(GEN_RET, gi)),
      customerRefId: gCust.code.replace('CUST-', 'REF-') + '-2026-' + pad(1000 + gi, 4),
      customerPo: 'PO-45009' + pad(10000 + gi * 37, 5),
      salesOrder: 'SO-2026' + pad(100 + gi * 3, 3),
      supplierInvoice: 'INV-2026-' + pad(1100 + gi * 5, 4),
      shippedDirectly: (gi % 6 === 0) ? 'Yes' : 'No',
      directComm: (gi % 3 === 0) ? 'Yes' : 'No',
      receivedApprPack: (gi % 5 === 0) ? 'No' : 'Yes',
      failureMode: gFm,
      symptoms: ft.sym,
      conclusion: gStageIdx >= 3 ? ft.concl : '',
      comment: gClosed ? '8D 报告已发送客户确认，投诉已结案归档。' : '正在按 8D 流程推进。'
    });
  }

  var complaints = heroComplaints.concat(generatedComplaints);

  var ROLE_FIELDS = [
    ['complaintOwner', '投诉负责人'], ['coordinator', '协调人'],
    ['verifier', '验证负责人'], ['reportOwner', '报告负责人']
  ];

  /* 「与我相关」按当前登录人在单据上是否承担任一角色实时计算（角色切换后子集会变化） */
  function isMine(c, uid) {
    return c.complaintOwner === uid || c.coordinator === uid ||
           c.verifier === uid || c.reportOwner === uid;
  }

  function myRoleIn(c, uid) {
    for (var i = 0; i < ROLE_FIELDS.length; i++) {
      if (c[ROLE_FIELDS[i][0]] === uid) { return ROLE_FIELDS[i][1]; }
    }
    return '';
  }

  /* ---------------- 样品 ---------------- */

  var samples = [
    { id: 'S-0722-01', complaintId: 'C202600722', customerSampleId: 'GM-WH-S01', qty: 4, uom: 'PCS', lotId: 'WDXG37205F0A', dateCode: '2641', assemblyCenter: 'ATGD', waferFab: 'ATMC', desc: '封装崩边样品（顶面近引脚侧）', marking: 'Nexperia 934068123456 YYWW2641', appArea: '装配前来料检验', reject: 'Yes', conclusion: 'Chipping 长度 0.3–0.5 mm，未伤及内部结构', failureType: '2 - Assembly related / 2c - Molding / 2ca - Package chipping' },
    { id: 'S-0722-02', complaintId: 'C202600722', customerSampleId: 'GM-WH-S02', qty: 4, uom: 'PCS', lotId: 'WDXG37205F0A', dateCode: '2641', assemblyCenter: 'ATGD', waferFab: 'ATMC', desc: '同批次对照样品（未崩边）', marking: 'Nexperia 934068123456 YYWW2641', appArea: '装配前来料检验', reject: 'No', conclusion: '外观正常，用于对比分析', failureType: '' },
    { id: 'S-0735-01', complaintId: 'C202600735', customerSampleId: 'HUA-SZ-S01', qty: 6, uom: 'PCS', lotId: 'WDXG37918B2C', dateCode: '2638', assemblyCenter: 'ATGD', waferFab: 'ATNN', desc: 'ESD 测试失效样品', marking: 'Nexperia 934071234567 YYWW2638', appArea: '整机 ESD 测试', reject: 'Yes', conclusion: '待验证', failureType: '' },
    { id: 'S-0703-01', complaintId: 'C202600703', customerSampleId: 'GM-YT-S01', qty: 18, uom: 'PCS', lotId: 'WDXG36402A1D', dateCode: '2604', assemblyCenter: 'ATGD', waferFab: 'ATMC', desc: 'HTRB 漏电超标样品', marking: 'Nexperia 934068123456 YYWW2604', appArea: '可靠性监控', reject: 'Yes', conclusion: '键合球脱离', failureType: '2 - Assembly related / 2a - Bond and wire / 2aa - Lifted ball bond' },
    { id: 'S-0690-01', complaintId: 'C202600690', customerSampleId: 'CON-FS-S01', qty: 9, uom: 'PCS', lotId: 'WDXG35771C8E', dateCode: '2601', assemblyCenter: 'ATGD', waferFab: 'ATNN', desc: '温度循环后开路样品', marking: 'Nexperia 934068789012 YYWW2601', appArea: '温度循环测试', reject: 'Yes', conclusion: '键合颈部断裂', failureType: '2 - Assembly related / 2a - Bond and wire / 2ab - Wire broken / neck break' },
    { id: 'S-0745-01', complaintId: 'C202600745', customerSampleId: 'HUA-SZ-S03', qty: 3, uom: 'PCS', lotId: 'WDXG38104D6F', dateCode: '2639', assemblyCenter: 'ATGD', waferFab: 'ATNN', desc: '表面附着物样品', marking: 'Nexperia 934071234567 YYWW2639', appArea: '整机返修', reject: 'Yes', conclusion: '待验证', failureType: '' }
  ];

  /* ---------------- 物流批次 ---------------- */

  var shipments = [
    { id: 'SH-0722-01', complaintId: 'C202600722', sender: 'U01', receiver: 'U03', status: '已签收', qty: 8, application: 'Yes', createdAt: '2026-09-15 10:20', startDate: '2026-09-15', carrier: '顺丰速运', tracking: 'SF1234567890123', targetDate: '2026-09-18', closeDate: '2026-09-17', comments: '客户加急寄出，用于崩边分析', sampleIds: ['S-0722-01', 'S-0722-02'] },
    { id: 'SH-0722-02', complaintId: 'C202600722', sender: 'U01', receiver: 'U03', status: '运输中', qty: 20, application: 'Yes', createdAt: '2026-09-22 16:05', startDate: '2026-09-22', carrier: 'DHL', tracking: 'DHL8877665544', targetDate: '2026-09-25', closeDate: null, comments: '同批次追加样品，验证包装改善效果', sampleIds: [] },
    { id: 'SH-0703-01', complaintId: 'C202600703', sender: 'U04', receiver: 'U03', status: '已签收', qty: 18, application: 'Yes', createdAt: '2026-08-26 09:40', startDate: '2026-08-26', carrier: '顺丰速运', tracking: 'SF9988776655443', targetDate: '2026-08-29', closeDate: '2026-08-28', comments: '整批发货', sampleIds: ['S-0703-01'] }
  ];

  /* ---------------- D2 验证任务与结果 ---------------- */

  var verificationTasks = [
    { id: 'VT-0722-01', complaintId: 'C202600722', sampleId: 'S-0722-01', owner: 'U03', planStart: '2026-09-17', targetEnd: '2026-09-23', status: '已完成', tests: '外观检查 / 扫描电镜 SEM / 断面分析', result: '崩边位于塑封体顶面，深度 0.12 mm，未伤及键合线', failureType: '2 - Assembly related / 2c - Molding / 2ca - Package chipping' },
    { id: 'VT-0722-02', complaintId: 'C202600722', sampleId: 'S-0722-02', owner: 'U03', planStart: '2026-09-17', targetEnd: '2026-09-23', status: '已完成', tests: '外观检查 / X-Ray', result: '对照组无异常', failureType: '' },
    { id: 'VT-0735-01', complaintId: 'C202600735', sampleId: 'S-0735-01', owner: 'U03', planStart: '2026-09-23', targetEnd: '2026-09-30', status: '进行中', tests: '电性测试 / 开封分析 / ESD 失效点定位', result: '', failureType: '' },
    { id: 'VT-0745-01', complaintId: 'C202600745', sampleId: 'S-0745-01', owner: 'U03', planStart: '2026-09-25', targetEnd: '2026-10-02', status: '待开始', tests: 'SEM / EDS 成分分析', result: '', failureType: '' }
  ];

  /* ---------------- D3 遏制措施 ---------------- */

  var containmentActions = [
    { id: 'CA-0722-01', complaintId: 'C202600722', nexSampleNumber: 'NEX-934068123456-01', customerSampleNumber: 'GM-WH-S01', plannedAction: '隔离客户端武汉工厂同批次库存并全检筛选', owner: 'U01', completedDate: '2026-09-16', status: '已完成', result: '共筛选 3,200 pcs，另发现 46 pcs 同类崩边，已换货' },
    { id: 'CA-0722-02', complaintId: 'C202600722', nexSampleNumber: 'NEX-934068123456-02', customerSampleNumber: 'GM-WH-S01', plannedAction: '内部成品仓同批次 100% 外观复检', owner: 'U04', completedDate: '2026-09-18', status: '已完成', result: '复检 12,400 pcs，发现 28 pcs 崩边，已隔离' },
    { id: 'CA-0722-03', complaintId: 'C202600722', nexSampleNumber: 'NEX-934068123456-03', customerSampleNumber: 'GM-WH-S02', plannedAction: '临时更换包装容器并加装防变形支撑衬垫', owner: 'U04', completedDate: '2026-09-25', status: '进行中', result: '首批改善包装已寄出，待客户端验证' },
    { id: 'CA-0729-01', complaintId: 'C202600729', nexSampleNumber: 'NEX-934068123456-11', customerSampleNumber: '—', plannedAction: '隔离产线在制品并对成型模具进行点检', owner: 'U06', completedDate: null, status: '进行中', result: '已完成 3 台模具点检，1 台待复检' }
  ];

  /* ---------------- D4 根因分析 ---------------- */

  var rootCauses = [
    {
      id: 'RC-0722-01', complaintId: 'C202600722', summary: '包装容器在运输堆码中受挤压变形，拆包旋开时产生机械应力，传导至器件顶面造成崩边',
      desc: '通过 3x5 Why 分析确认：\n\n1. 为什么器件顶面出现崩边？→ 拆包旋开容器时塑封体与容器边缘发生机械干涉。\n2. 为什么会产生机械干涉？→ 容器在运输中受堆码压力变形，内腔尺寸缩小。\n3. 为什么容器会变形？→ 现有 PP 材质容器壁厚 0.8 mm，抗压强度不足。\n4. 为什么选用该壁厚？→ 该规格沿用自 2023 年旧标准，未针对当前堆码高度重新校核。\n5. 为什么未重新校核？→ 包装变更评审流程未包含客户实际堆码高度输入。',
      risk: '中', riskNote: '外观类失效，不影响电性能，但客户产线已暂停上线，存在停线风险',
      org: '内部 - 封装工程', owner: 'U06', status: '已完成', createdAt: '2026-09-20 14:30', by: 'U06'
    },
    {
      id: 'RC-0722-02', complaintId: 'C202600722', summary: '来料检验抽样标准未覆盖包装完整性检查项',
      desc: '客户侧与我方出厂检验均未将「包装容器外观 / 尺寸完整性」纳入抽样检查项，导致变形容器流出。',
      risk: '低', riskNote: '流程类缺失，影响范围限于本批次',
      org: '内部 - 质量管理', owner: 'U04', status: '进行中', createdAt: '2026-09-22 09:15', by: 'U04'
    }
  ];

  /* 3x5 Why 内容（3 条路径 × 5 层） */
  var whyAnalysis = {
    complaintId: 'C202600722',
    rootCauseId: 'RC-0722-01',
    updatedAt: '2026-09-20 14:30',
    by: 'U06',
    paths: [
      { no: 1, layers: ['器件顶面出现崩边', '拆包旋开时塑封体与容器边缘机械干涉', '容器在运输堆码中受压变形，内腔尺寸缩小', 'PP 容器壁厚 0.8 mm，抗压强度不足', '规格沿用 2023 年旧标准，未按当前堆码高度重新校核'] },
      { no: 2, layers: ['崩边集中出现在容器四角位置', '四角为容器结构应力集中区', '容器四角无加强筋设计', '模具未设计加强筋结构', '包装设计规范未强制要求加强筋'] },
      { no: 3, layers: ['出货前未拦截变形容器', '出厂检验未含包装完整性检查项', '检验标准书未覆盖包装项', '标准书评审未邀请包装工程参与', '包装变更评审流程缺少质量部会签环节'] }
    ],
    aiUsed: false
  };

  /* ---------------- D5 纠正措施 ---------------- */

  var correctiveActions = [
    { id: 'PA-0722-01', complaintId: 'C202600722', rootCauseId: 'RC-0722-01', nexSample: 'NEX-934068123456-01', customerSample: 'GM-WH-S01', desc: '包装容器材质由 PP 变更为 PETG，壁厚增至 1.2 mm，四角增加加强筋', owner: 'U06', targetDate: '2026-10-10', status: '进行中' },
    { id: 'PA-0722-02', complaintId: 'C202600722', rootCauseId: 'RC-0722-01', nexSample: 'NEX-934068123456-02', customerSample: 'GM-WH-S01', desc: '包装设计规范增加「按客户实际堆码高度校核抗压强度」强制条款', owner: 'U04', targetDate: '2026-10-15', status: '待开始' },
    { id: 'PA-0722-03', complaintId: 'C202600722', rootCauseId: 'RC-0722-02', nexSample: 'NEX-934068123456-03', customerSample: 'GM-WH-S02', desc: '出厂检验标准书增加包装容器外观与尺寸完整性检查项', owner: 'U04', targetDate: '2026-10-08', status: '进行中' },
    { id: 'PA-0703-01', complaintId: 'C202600703', rootCauseId: 'RC-0703-01', nexSample: 'NEX-934068123456-21', customerSample: 'GM-YT-S01', desc: '清洗工序增加键合区表面污染监控，毛细管更换周期由 200k 降至 120k 次', owner: 'U06', targetDate: '2026-09-05', status: '已完成' }
  ];

  /* ---------------- D6 措施验证 ---------------- */

  var actionVerifications = [
    { id: 'AV-0722-01', complaintId: 'C202600722', actionId: 'PA-0722-01', actualDate: null, result: '', conclusion: '待验证', files: [] },
    { id: 'AV-0722-02', complaintId: 'C202600722', actionId: 'PA-0722-02', actualDate: null, result: '', conclusion: '待验证', files: [] },
    { id: 'AV-0722-03', complaintId: 'C202600722', actionId: 'PA-0722-03', actualDate: '2026-09-23', result: '新检验标准书已发布并完成产线培训，连续 5 批次出厂检验均覆盖包装项', conclusion: '验证通过', files: ['检验标准书 QI-2026-088.pdf'] },
    { id: 'AV-0703-01', complaintId: 'C202600703', actionId: 'PA-0703-01', actualDate: '2026-09-04', result: '1000h HTRB 验证 500 pcs 全部通过，漏电均低于规格上限', conclusion: '验证通过', files: ['HTRB-1000h-Report-20260904.pdf'] }
  ];

  /* ---------------- D7 预防再发生 ---------------- */

  var preventionFiles = [
    { id: 'PF-0722-01', complaintId: 'C202600722', nexSample: 'NEX-934068123456-01', customerSample: 'GM-WH-S01', program: 'FMEA', refNo: 'PFMEA-ASM-2026-014', status: '进行中', fileName: 'PFMEA-ASM-2026-014-v3.pdf', owner: 'U06' },
    { id: 'PF-0722-02', complaintId: 'C202600722', nexSample: 'NEX-934068123456-01', customerSample: 'GM-WH-S01', program: 'Control Plan', refNo: 'CP-ASM-2026-031', status: '进行中', fileName: '', owner: 'U04' },
    { id: 'PF-0722-03', complaintId: 'C202600722', nexSample: 'NEX-934068123456-02', customerSample: 'GM-WH-S02', program: 'SOP', refNo: 'SOP-PKG-2026-047', status: '已完成', fileName: 'SOP-PKG-2026-047-v2.pdf', owner: 'U06' },
    { id: 'PF-0722-04', complaintId: 'C202600722', nexSample: 'NEX-934068123456-03', customerSample: 'GM-WH-S02', program: 'Update on Flow', refNo: 'FLOW-PKG-2026-009', status: '待开始', fileName: '', owner: 'U04' },
    { id: 'PF-0703-01', complaintId: 'C202600703', nexSample: 'NEX-934068123456-21', customerSample: 'GM-YT-S01', program: 'OCAP', refNo: 'OCAP-ASM-2026-022', status: '已完成', fileName: 'OCAP-ASM-2026-022-v1.pdf', owner: 'U06' }
  ];

  /* ---------------- 8D 报告 ---------------- */

  var reports = [
    {
      id: 'RPT-0722-01', complaintId: 'C202600722', type: '中期报告', version: 'V1.2', status: '编制中',
      owner: 'U01', createdAt: '2026-09-21 11:20', updatedAt: '2026-09-23 17:05',
      startDate: null, targetDate: null, closeDate: null, sentAt: null, sentTo: [], cc: []
    },
    {
      id: 'RPT-0718-01', complaintId: 'C202600718', type: '终期报告', version: 'V2.0', status: '待审批',
      owner: 'U01', createdAt: '2026-09-16 09:30', updatedAt: '2026-09-22 15:40',
      startDate: null, targetDate: null, closeDate: null, sentAt: null, sentTo: [], cc: []
    },
    {
      id: 'RPT-0690-01', complaintId: 'C202600690', type: '终期报告', version: 'V1.0', status: '已发送',
      owner: 'U01', createdAt: '2026-08-08 14:00', updatedAt: '2026-08-12 10:15',
      startDate: '2026-08-12', targetDate: '2026-08-26', closeDate: '2026-08-12',
      sentAt: '2026-08-12 10:15', sentTo: ['李娜 / Na Li'], cc: ['U02']
    }
  ];

  /* 报告步骤 owner 分配（D1-D8）—— 章节名对齐 XTE-0071 模板原文 */
  var reportSteps = [
    { step: 'D1', en: 'MULTIDISCIPLINARY team', name: '成立团队', owner: 'U02', due: '2026-09-16', status: '已完成' },
    { step: 'D2', en: 'PROBLEM DESCRIPTION', name: '问题描述', owner: 'U03', due: '2026-09-17', status: '已完成' },
    { step: 'D3', en: 'CONTAINMENT ACTIONS', name: '遏制措施', owner: 'U04', due: '2026-09-19', status: '已完成' },
    { step: 'D4', en: 'ROOT CAUSE', name: '根因分析', owner: 'U06', due: '2026-09-23', status: '已完成' },
    { step: 'D5', en: 'POSSIBLE CORRECTIVE ACTION', name: '备选纠正措施', owner: 'U06', due: '2026-10-10', status: '进行中' },
    { step: 'D6', en: 'IMPLEMENTED CORRECTIVE ACTION', name: '已实施纠正措施', owner: 'U04', due: '2026-10-15', status: '进行中' },
    { step: 'D7', en: 'IMPLEMENTED SYSTEMIC CORRECTIVE ACTION', name: '系统性纠正措施', owner: 'U06', due: '2026-10-20', status: '待开始' },
    { step: 'D8', en: 'REPORTED BY / APPROVED BY / DISTRIBUTION LIST', name: '签署与分发', owner: 'U01', due: '2026-10-25', status: '待开始' }
  ];

  /* 报告正文内容
     结构严格对齐两份真实文件：
       · XTE-0071.docx（空白模板）—— 章节命名与字段
       · C2501869.docx（已填写样例）—— 版式与内容组织
     内部人员用 uid（渲染时经 QMS.user() 解析姓名与职务），外部人员直接给 name。 */
  var reportContent = {
    complaintId: 'C202600722',

    revisionHistory: [
      { date: '2026-09-20', change: 'Initial version', uid: 'U01' },
      { date: '2026-09-23', change: '补充 D4 根因分析与风险评估、D5/D6 措施清单', uid: 'U01' }
    ],

    D1: {
      team: [
        { func: 'Problem Owner', uid: 'U02' },
        { func: 'Team Leader', uid: 'U01' },
        { func: 'Team Member', uid: 'U03' },
        { func: 'Team Member', uid: 'U04' },
        { func: 'Team Member', uid: 'U06' },
        { func: 'QA / QS Representative', uid: 'U05' }
      ]
    },

    D2: {
      sections: [
        { title: 'Description of received unit',
          body: '客户寄回 8 pcs（4 pcs 崩边样品 + 4 pcs 同批次对照样品），采用防静电袋 + 防变形托盘包装。样品丝印 934068123456 / YYWW2641，LOT ID WDXG37205F0A。',
          figure: '寄回样品外观' },
        { title: 'Visual inspection results',
          body: '在光学显微镜下目检：崩边位于塑封体顶面靠近引脚一侧，长度 0.3–0.5 mm，肉眼可见。结果：确认为塑封体机械崩边，崩边处未见烧蚀或污染痕迹。',
          figure: '目检照片（崩边位置）' },
        { title: 'SEM / Cross-section analysis',
          body: '对崩边样品做扫描电镜与断面分析：崩边深度 0.12 mm，止于塑封体表层，未伤及键合线与芯片表面。',
          figure: 'SEM 断面图' },
        { title: 'X-Ray inspection',
          body: 'X-Ray 检查引线框架与键合线：未见键合偏移、空洞或内部裂纹等异常。',
          figure: 'X-Ray 图' },
        { title: 'Final test comparison',
          body: '使用量产终测程序对比良品参考件：全部电性参数均在规格内。结论：本次为外观类失效，不影响电性能。',
          figure: '' }
      ]
    },

    D3: {
      actions: [
        { desc: '隔离客户端武汉工厂同批次库存并 100% 全检筛选', uid: 'U01', closedDate: '2026-09-16',
          result: '共筛选 3,200 pcs，另发现 46 pcs 同类崩边，已完成换货' },
        { desc: '内部成品仓同批次 100% 外观复检', uid: 'U04', closedDate: '2026-09-18',
          result: '复检 12,400 pcs，发现 28 pcs 崩边，已隔离' },
        { desc: '检查该批次生产与设备维护记录', uid: 'U06', closedDate: '2026-09-16',
          result: '无异常停机与设备维修记录' },
        { desc: '检查该批次是否触发 OCAP（Out of Control Action Plan）', uid: 'U04', closedDate: '2026-09-16',
          result: '该批次无 OCAP 记录' },
        { desc: '临时更换包装容器并加装防变形支撑衬垫', uid: 'U04', closedDate: '',
          result: '改善包装首批已寄出，待客户端验证（进行中）' }
      ]
    },

    D4: {
      narrative: '依据生产历史记录确认：该批次无异常停机与设备维修，也未触发 OCAP。结合失效模式分析，崩边最可能由运输堆码过程中包装容器受压变形引起——容器内腔尺寸缩小后，客户拆包旋开时塑封体顶面与容器边缘发生机械干涉，形成 0.3–0.5 mm 崩边。崩边深度止于塑封体表层，未伤及键合线与芯片，属外观类失效。',
      whyQA: [
        { q: 'How can a deformed container cause package chipping?',
          a: '容器受压变形后内腔尺寸缩小，拆包旋开时塑封体顶面与容器边缘发生机械干涉，产生 0.3–0.5 mm 崩边。' },
        { q: 'Why does the container deform?',
          a: '现用 PP 容器壁厚 0.8 mm，四角无加强筋，抗压强度不足以承受客户端的实际堆码高度。' },
        { q: 'Why is the wall thickness / structure insufficient?',
          a: '该规格沿用 2023 年旧标准，未按客户当前堆码高度重新校核；包装设计规范也未强制要求加强筋结构。' },
        { q: 'Why did the problem escape our inspection?',
          a: '客户侧与我方出厂检验均未将「包装容器外观 / 尺寸完整性」纳入抽样检查项，变形容器得以流出。' }
      ],
      risk: [
        '该变形容器为运输过程偶发，未重复出现于后续批次；预计单个 mold shot 内受影响器件数量有限。',
        '按客户武汉工厂年用量估算，失效比例约 0.04 ppb 量级（同批次 12,400 pcs 复检发现 28 pcs），属极低概率偶发外观类失效。'
      ],
      attachments: [
        '3x5Why_包装崩边_v2.xlsx',
        '鱼骨图_包装崩边.png',
        'SEM_断面分析_S-0722-01.pdf'
      ]
    },

    D5: {
      actions: [
        { no: 1, action: '包装容器材质由 PP 变更为 PETG，壁厚由 0.8 mm 增至 1.2 mm', uid: 'U06',
          targetDate: '2026-10-10', status: 'In Progress', remark: '' },
        { no: 2, action: '容器四角增加加强筋结构', uid: 'U06',
          targetDate: '2026-10-10', status: 'In Progress', remark: '' },
        { no: 3, action: '包装设计规范增加「按客户实际堆码高度校核抗压强度」强制条款', uid: 'U04',
          targetDate: '2026-10-15', status: 'Planned', remark: '' },
        { no: 4, action: '出厂检验标准书增加包装容器外观与尺寸完整性检查项', uid: 'U04',
          targetDate: '2026-10-08', status: 'Done', remark: 'QI-2026-088' }
      ]
    },

    D6: {
      actions: [
        { no: 1, action: '出厂检验标准书增加包装容器外观与尺寸完整性检查项', uid: 'U04',
          targetDate: '2026-10-08', status: 'Done', remark: '连续 5 批次出厂检验均覆盖包装项' },
        { no: 2, action: '包装容器材质由 PP 变更为 PETG，壁厚增至 1.2 mm', uid: 'U06',
          targetDate: '2026-10-10', status: 'In Progress', remark: '首批改善包装待客户端验证' }
      ]
    },

    D7: {
      desc: '将包装设计校核要求写入包装设计规范与管理体系文件，从流程上消除同类根因；同步更新包装变更评审流程，增加「客户实际堆码高度」为强制输入项。',
      verification: '待包装工程与质量部会签后发布新版规范（目标 2026-10-15）。',
      readAcross: '横向展开至其他使用同类 PP 容器的产品系列（共 6 个料号），并纳入新供应商准入检查清单。'
    },

    D8: {
      signoff: [
        { func: 'Reported By', uid: 'U01', date: '2026-09-23' },
        { func: 'Approved by', uid: 'U02', date: '' },
        { func: 'Approved by', uid: 'U05', date: '' }
      ],
      distribution: [
        '通用汽车武汉工厂 质量部 — 张伟',
        '博世汽车部件（苏州）有限公司 质量部 — SQE',
        'Nexperia Sales Quality — 刘丹茜',
        'Nexperia BG Quality — 陈志远'
      ]
    }
  };

  /* ---------------- 附件 ---------------- */

  var attachments = [
    { id: 'A-01', complaintId: 'C202600722', biz: '失效描述', name: '客户崩边照片-1.jpg', size: '1.8 MB', type: 'img', by: 'U01', at: '2026-09-08 09:30' },
    { id: 'A-02', complaintId: 'C202600722', biz: '失效描述', name: 'Customer_Complaint_Form_GM-WH-SC-2026-0913.pdf', size: '842 KB', type: 'pdf', by: 'U01', at: '2026-09-08 09:32' },
    { id: 'A-03', complaintId: 'C202600722', biz: '失效描述', name: 'D0_G8D_Report.docx', size: '256 KB', type: 'doc', by: 'U01', at: '2026-09-08 09:35' },
    { id: 'A-04', complaintId: 'C202600722', biz: '验证任务', name: 'SEM_断面分析_S-0722-01.pdf', size: '3.2 MB', type: 'pdf', by: 'U03', at: '2026-09-22 16:40' },
    { id: 'A-05', complaintId: 'C202600722', biz: '验证任务', name: 'X-Ray_对照_S-0722-02.jpg', size: '1.1 MB', type: 'img', by: 'U03', at: '2026-09-22 16:42' },
    { id: 'A-06', complaintId: 'C202600722', biz: '根因分析', name: '3x5Why_包装崩边_v2.xlsx', size: '184 KB', type: 'xls', by: 'U06', at: '2026-09-20 14:25' },
    { id: 'A-07', complaintId: 'C202600722', biz: '报告', name: '8D_Report_C202600722_V1.2.pdf', size: '2.4 MB', type: 'pdf', by: 'U01', at: '2026-09-23 17:05' }
  ];

  /* ---------------- 沟通日志 ---------------- */

  var commLogs = [
    { id: 'CL-0722-01', complaintId: 'C202600722', at: '2026-09-21 11:35', by: 'U01', to: ['张伟 / Wei Zhang'], cc: ['U02'], subject: '【中期报告】C202600722 封装崩边 - D0-D3 进展说明', attachment: '8D_Report_C202600722_V1.1.pdf', status: '已送达' },
    { id: 'CL-0718-01', complaintId: 'C202600718', at: '2026-09-16 10:05', by: 'U01', to: ['李娜 / Na Li'], cc: ['U02', 'U05'], subject: '【中期报告】C202600718 焊点空洞 - D0-D5 进展说明', attachment: '8D_Report_C202600718_V1.3.pdf', status: '已送达' },
    { id: 'CL-0690-01', complaintId: 'C202600690', at: '2026-08-12 10:15', by: 'U01', to: ['李娜 / Na Li'], cc: ['U02'], subject: '【终期报告】C202600690 键合颈部断裂 - 结案通知', attachment: '8D_Report_C202600690_V1.0.pdf', status: '已送达' }
  ];

  /* ---------------- 流程日志 ---------------- */

  var flowLogs = {
    'C202600722': [
      { at: '2026-09-08 09:24', by: 'U01', action: '登记投诉', detail: '创建投诉单 C202600722，状态「登记-已启动」，阶段 D0', type: 'done' },
      { at: '2026-09-08 09:35', by: 'U01', action: '上传附件', detail: '上传 3 个附件（客户照片、投诉单、D0 G8D Report）', type: 'done' },
      { at: '2026-09-10 14:02', by: 'U02', action: '指派负责人', detail: '验证负责人 王振宇；报告负责人 马晓然', type: 'done' },
      { at: '2026-09-15 08:30', by: 'U01', action: '登记样品与物流', detail: '登记样品 2 条，创建物流批次 SH-0722-01（顺丰 SF1234567890123）', type: 'done' },
      { at: '2026-09-15 10:20', by: 'U02', action: '遏制措施判定', detail: '登记阶段判定：需要遏制措施', type: 'warn' },
      { at: '2026-09-16 11:40', by: 'U01', action: '遏制措施完成', detail: 'CA-0722-01 客户端隔离全检完成，换货 46 pcs', type: 'done' },
      { at: '2026-09-17 09:15', by: 'U03', action: '创建验证任务', detail: '创建 VT-0722-01 / VT-0722-02，排期 09-17 ~ 09-23', type: 'done' },
      { at: '2026-09-22 17:20', by: 'U03', action: '验证结论', detail: '投诉成立（Valid = Yes），崩边深度 0.12 mm 未伤及键合线', type: 'done' },
      { at: '2026-09-22 17:25', by: 'U02', action: '阶段流转', detail: 'D2 → D3 遏制措施', type: 'done' },
      { at: '2026-09-23 10:10', by: 'U06', action: '创建根因条目', detail: '创建 RC-0722-01（包装容器抗压强度不足）', type: 'done' },
      { at: '2026-09-23 16:50', by: 'U04', action: '创建根因条目', detail: '创建 RC-0722-02（检验标准未覆盖包装项）', type: 'done' },
      { at: '2026-09-24 09:05', by: 'U02', action: '超期提醒', detail: '目标日期 2026-09-22 已超期 2 天，已发送邮件提醒投诉负责人', type: 'warn' },
      { at: '2026-09-24 09:05', by: 'U08', action: '邮件通知', detail: 'TPT 超期预警邮件已发送至 U01 / U02 / U04 / U06', type: 'active' }
    ]
  };

  /* ---------------- D4 待办 / 首页 ---------------- */

  /* 待办由「未结案投诉 + 待审批报告」派生，而不是手写清单：
     这样待办数量与台账数据自动保持一致，切换角色时各角色的工作量差异也是真实的。
     只纳入「已超期 / 已进入 D4 及以后 / 优先级为非常紧急」的单据，避免出现几十条无意义待办。 */

  var TODO_TYPE_BY_STAGE = {
    D0: '样品物流', D1: '样品物流', D2: '验证任务', D3: '遏制措施',
    D4: '根因分析', D5: '纠正措施', D6: '措施验证', D7: '预防文件', D8: '报告编制'
  };
  var TODO_ACTION_BY_STAGE = {
    D0: '待补录样品与物流信息', D1: '待补录样品与物流信息', D2: '失效分析结果待录入',
    D3: '遏制措施待跟踪闭环', D4: '根因分析待完成', D5: '纠正措施待分配与推进',
    D6: '措施验证结果待反馈', D7: '预防文件更新待完成', D8: '8D 报告待编制与提交'
  };
  var TODO_PERSONA = {
    '样品物流': ['sales', 'qe'], '验证任务': ['fa', 'qe'], '遏制措施': ['qe', 'owner'],
    '根因分析': ['qe', 'owner'], '纠正措施': ['qe', 'owner'], '措施验证': ['qe', 'owner'],
    '预防文件': ['qe', 'owner'], '报告编制': ['sales', 'owner'], '待审批报告': ['appr']
  };

  function panelOfStage(stage) {
    return (stage === 'D0' || stage === 'D1') ? 'd01' : stage.toLowerCase();
  }

  /* 待办派给该单据上对应阶段的责任人（而不是按任务类型摊给所有角色），
     这样「我的待办」才真的是「我的」，且切换角色后清单会变。 */
  var USER_PERSONA = {};
  personas.forEach(function (pp) {
    (USER_PERSONA[pp.user] = USER_PERSONA[pp.user] || []).push(pp.key);
  });

  function assigneeOf(c, stage) {
    if (stage === 'D0' || stage === 'D1') { return c.coordinator; }
    if (stage === 'D2') { return c.verifier || c.coordinator; }
    if (stage === 'D6') { return c.verifier || c.complaintOwner; }
    if (stage === 'D8') { return c.reportOwner || c.complaintOwner; }
    return c.complaintOwner;
  }

  function personaOf(uid, fallback) {
    var keys = USER_PERSONA[uid];
    return (keys && keys.length) ? keys : (fallback || ['qe']);
  }

  var todos = [];

  complaints.filter(function (c) {
    if (c.closeDate) { return false; }
    var idx = STAGE_ORDER_ALL.indexOf(c.stage);
    return overdueDays(c.targetDate) > 0 || idx >= 4 || c.priority === 'P1';
  }).forEach(function (c, i) {
    var tType = TODO_TYPE_BY_STAGE[c.stage] || '报告编制';
    var who = assigneeOf(c, c.stage);
    todos.push({
      id: 'T-' + pad(i + 1, 2),
      type: tType,
      title: c.id + ' ' + (c.failureMode || '质量问题') + ' - ' + (TODO_ACTION_BY_STAGE[c.stage] || '待处理'),
      complaintId: c.id,
      stage: panelOfStage(c.stage),
      assignee: who,
      due: c.targetDate,
      status: c.status.split('-')[1] || c.status,
      persona: personaOf(who, TODO_PERSONA[tType]),
      urgent: overdueDays(c.targetDate) > 0 || c.priority === 'P1'
    });
  });

  reports.filter(function (r) { return r.status === '待审批'; }).forEach(function (r, i) {
    todos.push({
      id: 'T-A' + (i + 1),
      type: '待审批报告',
      title: r.id + ' ' + r.type + '待审批',
      complaintId: r.complaintId,
      stage: 'd8',
      due: TODAY,
      status: '待审批',
      persona: ['appr'],
      urgent: true
    });
  });

  var announcements = [
    { id: 'N-01', title: 'QMS 问题解决管理系统一期上线通知', at: '2026-10-05 09:00', by: 'U08', pinned: true, body: '各位同事：\n\nQMS 问题解决管理系统一期将于 2026-10-05 正式上线，替代原 Champ 系统。一期覆盖客户投诉信息登记、样品物流登记、失效分析任务排期与结果录入、8D 报告编制与审批、措施跟踪的完整闭环。\n\n请注意：\n1. 原 Champ 系统历史数据不迁移，系统内从上线日起记录新单据。\n2. 通知统一走公司邮箱，审批统一走 OA 审批流。\n3. 投诉 ID 统一采用 C + 4 位年 + 5 位序号格式（如 C202600722）。\n\n操作手册见「知识中心」模块。' },
    { id: 'N-02', title: 'TPT 目标值调整通知（2026-10 起生效）', at: '2026-09-22 15:30', by: 'U08', pinned: false, body: '按 BG Quality 决议，自 2026-10 起 TPT 目标调整为：\n\n· 非常紧急：目标日期 = 开始日期 + 7 天\n· 紧急：目标日期 = 开始日期 + 10 天\n· 标准：目标日期 = 开始日期 + 14 天\n\n样品登记后 5 个工作日提醒完成 FA。系统将按新目标自动重算并发送提醒。' },
    { id: 'N-03', title: '8D 报告模板更新为 XTE-0071', at: '2026-09-20 11:00', by: 'U08', pinned: false, body: '8D 报告正式模板已确认为 XTE-0071 8D Problem Report（技术报告版式），系统内自动生成的报告将统一使用该模板。\n\n章节结构：D1 跨职能团队 / D2 问题描述 / D3 遏制措施 / D4 根本原因 / D5 备选纠正措施 / D6 已实施纠正措施 / D7 系统性纠正措施 / D8 签署与分发。\n\n注：模板与样例报告在 D7 / D8 章节口径上存在差异，已提请业务方确认。' }
  ];

  /* ---------------- 报表数据 ---------------- */

  var kpi = {
    validComplaints: { value: 34, target: 30, unit: '', trend: 'up', delta: '+4', period: '2026-09（当月）', owner: 'BG Q' },
    complaintTpt:    { value: 21.4, target: 18, unit: '天', trend: 'down', delta: '-1.2', period: '2026-09（当月均值）', owner: 'Sales Quality' },
    customerIncident:{ value: 47, target: 40, unit: '起', trend: 'up', delta: '+7', period: '2026-09（当月）', owner: 'BG Q' }
  };

  var tptTrend = [
    { month: 'M2501', tpt3d: 4.2, tpt8d: 24.1 }, { month: 'M2502', tpt3d: 3.8, tpt8d: 22.6 },
    { month: 'M2503', tpt3d: 4.6, tpt8d: 26.3 }, { month: 'M2504', tpt3d: 3.4, tpt8d: 20.8 },
    { month: 'M2505', tpt3d: 3.9, tpt8d: 23.5 }, { month: 'M2506', tpt3d: 3.1, tpt8d: 19.7 },
    { month: 'M2507', tpt3d: 4.4, tpt8d: 25.2 }, { month: 'M2508', tpt3d: 4.9, tpt8d: 27.8 },
    { month: 'M2509', tpt3d: 4.1, tpt8d: 23.9 }, { month: 'M2510', tpt3d: 3.6, tpt8d: 21.3 },
    { month: 'M2511', tpt3d: 3.3, tpt8d: 20.1 }, { month: 'M2512', tpt3d: 3.0, tpt8d: 18.6 }
  ];

  var pareto = [
    { mode: 'Package chipping',    count: 28 },
    { mode: 'Solder void',         count: 22 },
    { mode: 'Lifted ball bond',    count: 16 },
    { mode: 'ESD damage',          count: 11 },
    { mode: 'Wire bond broken',    count: 8 },
    { mode: 'Contamination',       count: 6 },
    { mode: 'Lead bent',           count: 4 },
    { mode: 'Die crack',           count: 2 }
  ];

  var byCustomer = [
    { customer: '博世汽车部件（苏州）', count: 26 },
    { customer: '大陆汽车电子（芜湖）', count: 19 },
    { customer: '深圳华为技术',       count: 14 },
    { customer: '采埃孚（中国）',     count: 9 },
    { customer: '其他',               count: 7 }
  ];

  var reportStatus = [
    { status: '编制中', count: 9,  color: 'badge-info' },
    { status: '待审批', count: 5,  color: 'badge-warning' },
    { status: '已发送', count: 14, color: 'badge-primary' },
    { status: '已结案', count: 11, color: 'badge-success' },
    { status: '已超期', count: 3,  color: 'badge-danger' }
  ];

  /* ---------------- 系统管理 ---------------- */

  var mdItems = [
    { group: '投诉类型', code: 'CT-01', cn: '技术投诉 - 复杂',   en: 'Technical Complaint - Complex',    status: '启用', order: 1 },
    { group: '投诉类型', code: 'CT-02', cn: '技术投诉 - 非复杂', en: 'Technical Complaint - Non-complex', status: '启用', order: 2 },
    { group: '投诉类型', code: 'CT-03', cn: '物流投诉',          en: 'Logistics Complaint',               status: '启用', order: 3 },
    { group: '投诉类型', code: 'CT-04', cn: '商务投诉',          en: 'Commercial Complaint',              status: '启用', order: 4 },
    { group: '投诉类型', code: 'CT-05', cn: '分析申请',          en: 'Analysis Request',                  status: '启用', order: 5 },
    { group: '投诉类型', code: 'CT-06', cn: '内部投诉',          en: 'Internal Complaint',                status: '启用', order: 6 },
    { group: '优先级',   code: 'PR-01', cn: '非常紧急',          en: 'Critical',  status: '启用', order: 1 },
    { group: '优先级',   code: 'PR-02', cn: '紧急',              en: 'Urgent',    status: '启用', order: 2 },
    { group: '优先级',   code: 'PR-03', cn: '标准',              en: 'Standard',  status: '启用', order: 3 },
    { group: '失效位置', code: 'FL-01', cn: '应用测试',          en: 'Application Test',   status: '启用', order: 1 },
    { group: '失效位置', code: 'FL-02', cn: '产线拒收',          en: 'Line Rejection',     status: '启用', order: 2 },
    { group: '失效位置', code: 'FL-03', cn: '可靠性监控',        en: 'Reliability Monitor', status: '启用', order: 3 },
    { group: '失效位置', code: 'FL-04', cn: '客户来料检验',      en: 'Incoming Inspection', status: '启用', order: 4 },
    { group: '失效位置', code: 'FL-05', cn: '客户端装配',        en: 'Customer Assembly',  status: '启用', order: 5 },
    { group: '失效位置', code: 'FL-06', cn: '终端用户失效',      en: 'End User Failure',   status: '停用', order: 6 },
    { group: '失效模式', code: 'FM-01', cn: '封装崩边',          en: 'Package chipping',  status: '启用', order: 1 },
    { group: '失效模式', code: 'FM-02', cn: '键合球脱离',        en: 'Lifted ball bond',  status: '启用', order: 2 }
  ];

  var tptConfig = [
    { node: '样品登记 → FA 完成', workdays: 5,  basis: '全部优先级', desc: '登记 samples 后 5 个工作日提醒完成失效分析' },
    { node: '投诉登记 → D3 遏制完成', workdays: 7,  basis: '非常紧急', desc: 'D3 阶段遏制措施完成时限' },
    { node: '投诉登记 → D3 遏制完成', workdays: 10, basis: '紧急',     desc: 'D3 阶段遏制措施完成时限' },
    { node: '投诉登记 → D3 遏制完成', workdays: 14, basis: '标准',     desc: 'D3 阶段遏制措施完成时限' },
    { node: '投诉登记 → D8 结案',     workdays: 30, basis: '全部优先级', desc: 'Target(8D)，超期自动升级提醒' }
  ];

  var interfaces = [
    { name: 'SAP 客户主数据',       dir: '入', system: 'SAP',      status: '正常', success: 100.0, lastRun: '2026-09-24 06:00', avgMs: 820,  records: '1,284', note: '客户编号 / 名称 / 地址 / 联系人 / Ship-To' },
    { name: 'PLM/SAP 产品主数据',   dir: '入', system: 'PLM/SAP',  status: '正常', success: 99.8,  lastRun: '2026-09-24 06:05', avgMs: 1140, records: '8,472', note: '12NC/9NC 物料编码与产品描述' },
    { name: 'MDM/HR 人员主数据',    dir: '入', system: 'MDM/HR',   status: '正常', success: 100.0, lastRun: '2026-09-24 06:10', avgMs: 640,  records: '3,915', note: '姓名 / 邮箱 / 部门 / 直线经理' },
    { name: 'MES 生产主数据',       dir: '入', system: 'MES',      status: '警告', success: 94.2,  lastRun: '2026-09-24 06:15', avgMs: 2380, records: '12,036', note: '工序 / 工序组 / 生产线机台' },
    { name: 'OA 审批流',            dir: '双向', system: 'OA',     status: '正常', success: 99.6,  lastRun: '2026-09-24 09:05', avgMs: 460,  records: '58',    note: '审批任务推送与状态回写' },
    { name: '企业邮箱',             dir: '出', system: 'Exchange', status: '正常', success: 99.9,  lastRun: '2026-09-24 09:05', avgMs: 320,  records: '216',   note: '任务通知 / 预警 / 审批邮件' },
    { name: 'BI 平台',              dir: '出', system: 'BI',       status: '正常', success: 100.0, lastRun: '2026-09-24 07:00', avgMs: 1520, records: '—',     note: '业绩报表取数' }
  ];

  var auditLogs = [
    { at: '2026-09-24 09:05:12', user: 'U08', action: '邮件通知', target: 'C202600722', detail: 'TPT 超期预警邮件发送至 4 人', ip: '10.24.31.77' },
    { at: '2026-09-24 08:52:40', user: 'U02', action: '字段修改', target: 'C202600722', detail: '协调人：李思远 → 马晓然', ip: '10.24.18.42' },
    { at: '2026-09-23 17:05:33', user: 'U01', action: '报告导出', target: 'RPT-0722-01', detail: '导出 8D_Report_C202600722_V1.2.pdf', ip: '10.24.18.20' },
    { at: '2026-09-23 16:50:02', user: 'U04', action: '新建', target: 'RC-0722-02', detail: '创建根因条目', ip: '10.24.22.108' },
    { at: '2026-09-23 10:10:18', user: 'U06', action: '新建', target: 'RC-0722-01', detail: '创建根因条目', ip: '10.24.31.15' },
    { at: '2026-09-23 09:02:44', user: 'U01', action: '登录', target: '—', detail: 'SSO 登录成功（OAuth2）', ip: '10.24.18.20' },
    { at: '2026-09-22 17:25:09', user: 'U02', action: '状态流转', target: 'C202600722', detail: '阶段 D2 → D3', ip: '10.24.18.42' },
    { at: '2026-09-22 17:20:51', user: 'U03', action: '字段修改', target: 'C202600722', detail: '是否有效：空 → Yes', ip: '10.24.19.66' }
  ];

  /* ---------------- 工具函数 ---------------- */

  function pad(n, w) { var s = String(n); while (s.length < w) { s = '0' + s; } return s; }

  /** 生成下一个投诉 ID：C + 4位年 + 5位序号 */
  function nextComplaintId() {
    var year = 2026;
    var max = 0;
    complaints.forEach(function (c) {
      var m = /^C(\d{4})(\d{5})$/.exec(c.id);
      if (m && Number(m[1]) === year) { max = Math.max(max, Number(m[2])); }
    });
    return 'C' + year + pad(max + 1, 5);
  }

  /** 开始日期 = 创建日期 + 7 天 */
  function calcStartDate(createdDateStr) {
    var d = new Date(createdDateStr.replace(' ', 'T'));
    d.setDate(d.getDate() + 7);
    return d.toISOString().slice(0, 10);
  }

  /** 目标日期 = 开始日期 + 优先级天数 */
  function calcTargetDate(startDateStr, priorityCode) {
    var p = md.priority.filter(function (x) { return x.code === priorityCode; })[0];
    var days = p ? p.days : 14;
    var d = new Date(startDateStr + 'T00:00:00');
    d.setDate(d.getDate() + days);
    return d.toISOString().slice(0, 10);
  }

  /** 日期差（天） */
  function dayDiff(a, b) {
    var d1 = new Date(a + 'T00:00:00'), d2 = new Date(b + 'T00:00:00');
    return Math.round((d2 - d1) / 86400000);
  }

  /** 相对今天的超期天数，>0 表示已超期 */
  function overdueDays(targetDate) {
    if (!targetDate) { return 0; }
    return dayDiff(targetDate, TODAY);
  }

  function user(id) { return users[id] || { id: id, name: id, en: id }; }
  function customer(code) { return customers.filter(function (c) { return c.code === code; })[0] || {}; }
  function product(code) { return products.filter(function (p) { return p.code === code; })[0] || {}; }
  function priorityInfo(code) { return md.priority.filter(function (p) { return p.code === code; })[0] || md.priority[2]; }
  function complaint(id) { return complaints.filter(function (c) { return c.id === id; })[0] || null; }

  /* 8D 阶段定义（D0-D8） */
  var stages = [
    { code: 'D0', name: '问题登记' },
    { code: 'D1', name: '成立团队' },
    { code: 'D2', name: '验证与问题定义' },
    { code: 'D3', name: '遏制措施' },
    { code: 'D4', name: '根因分析' },
    { code: 'D5', name: '纠正措施' },
    { code: 'D6', name: '措施实施与验证' },
    { code: 'D7', name: '预防再发生' },
    { code: 'D8', name: '报告与结案' }
  ];

  /* ---------------- 导出 ---------------- */

  return {
    TODAY: TODAY,
    users: users, roles: roles, personas: personas, stages: stages,
    md: md, failureTypes: failureTypes, customers: customers, products: products,
    complaints: complaints, samples: samples, shipments: shipments,
    verificationTasks: verificationTasks, containmentActions: containmentActions,
    rootCauses: rootCauses, whyAnalysis: whyAnalysis,
    correctiveActions: correctiveActions, actionVerifications: actionVerifications,
    preventionFiles: preventionFiles, reports: reports, reportSteps: reportSteps,
    reportContent: reportContent, attachments: attachments,
    commLogs: commLogs, flowLogs: flowLogs, todos: todos, announcements: announcements,
    kpi: kpi, tptTrend: tptTrend, pareto: pareto, byCustomer: byCustomer, reportStatus: reportStatus,
    mdItems: mdItems, tptConfig: tptConfig, interfaces: interfaces, auditLogs: auditLogs,

    nextComplaintId: nextComplaintId,
    calcStartDate: calcStartDate,
    calcTargetDate: calcTargetDate,
    overdueDays: overdueDays,
    dayDiff: dayDiff,
    user: user, customer: customer, product: product,
    priorityInfo: priorityInfo, complaint: complaint,
    isMine: isMine, myRoleIn: myRoleIn
  };
})();
