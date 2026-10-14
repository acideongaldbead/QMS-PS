package com.nexperia.qms.complaint;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.config.PriorityProperties;
import com.nexperia.qms.complaint.dto.ComplaintLabels;
import com.nexperia.qms.complaint.dto.ComplaintRequests;
import com.nexperia.qms.complaint.dto.ComplaintResponses;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.FailureDescriptionMapper;
import com.nexperia.qms.complaint.mapper.ProductInfoMapper;
import com.nexperia.qms.complaint.mapper.QualityPartnerMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.complaint.mapper.SampleMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Registration of a customer complaint (D0-D1, requirement 3.1).
 *
 * A newly registered complaint lands on <b>D1 "成立团队"</b>, not D0: the
 * registration form captures the multidisciplinary roles (complaint owner,
 * coordinator, verification owner, report owner), which is exactly what D1
 * describes, so the act of registering completes D0 and D1 together. Confirmed
 * with the business on 2026-10-13.
 */
@Service
public class ComplaintService {

    /** status_code seeded by the baseline for a freshly registered complaint. */
    private static final String STATUS_REGISTERED = "COMPLAINT_S01";

    /** Phase 1 registers 8D only; 4C is reserved for phase 2 (Q-02). */
    private static final String PROCESS_TYPE_8D = "8D";

    /** D0 (problem registration) and D1 (form the team) both complete on registration. */
    private static final String STAGE_FORM_TEAM = "D1";

    /** Requirement 3.1.2: the start date defaults to the creation date plus 7 days. */
    private static final int START_DATE_OFFSET_DAYS = 7;

    /** Page sizes the ledger offers; any other value falls back to the default. */
    private static final List<Integer> LEDGER_PAGE_SIZES = List.of(20, 50, 100);
    private static final int LEDGER_DEFAULT_PAGE_SIZE = 20;

    /** A workbook of more rows than this is not a "list export" any more. */
    private static final int LEDGER_EXPORT_MAX_ROWS = 5000;

    private final ComplaintMapper complaintMapper;
    private final QualityPartnerMapper qualityPartnerMapper;
    private final ProductInfoMapper productInfoMapper;
    private final FailureDescriptionMapper failureDescriptionMapper;
    private final SampleMapper sampleMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final PriorityProperties priorityProperties;
    private final AuditLogService auditLogService;
    private final FailureTypeChainValidator failureTypeChainValidator;
    private final LedgerExcelWriter ledgerExcelWriter;

    public ComplaintService(ComplaintMapper complaintMapper,
                            QualityPartnerMapper qualityPartnerMapper,
                            ProductInfoMapper productInfoMapper,
                            FailureDescriptionMapper failureDescriptionMapper,
                            SampleMapper sampleMapper,
                            ReferenceMapper referenceMapper,
                            DocumentNumberService documentNumberService,
                            PriorityProperties priorityProperties,
                            AuditLogService auditLogService,
                            FailureTypeChainValidator failureTypeChainValidator,
                            LedgerExcelWriter ledgerExcelWriter) {
        this.complaintMapper = complaintMapper;
        this.qualityPartnerMapper = qualityPartnerMapper;
        this.productInfoMapper = productInfoMapper;
        this.failureDescriptionMapper = failureDescriptionMapper;
        this.sampleMapper = sampleMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.priorityProperties = priorityProperties;
        this.auditLogService = auditLogService;
        this.failureTypeChainValidator = failureTypeChainValidator;
        this.ledgerExcelWriter = ledgerExcelWriter;
    }

    /**
     * Validates, numbers and stores a new complaint together with its 1:1 blocks
     * and samples. One transaction: a complaint never exists without its detail
     * rows, which is what child-table deletion cascades rely on.
     */
    @Transactional
    public ComplaintResponses.Created create(ComplaintRequests.Create request) {
        validateReferences(request);

        LocalDate startDate = resolveStartDate(request.header());
        LocalDate targetDate = resolveTargetDate(request.header(), startDate);

        // Number only after validation, so a rejected request does not consume a
        // sequence value and leave a gap in the complaint numbers.
        String complaintId = documentNumberService.nextComplaintId();

        Complaint complaint = new Complaint();
        complaint.setComplaintId(complaintId);
        complaint.setStatusCode(STATUS_REGISTERED);
        complaint.setCurrentStage(STAGE_FORM_TEAM);
        complaint.setProcessType(PROCESS_TYPE_8D);
        complaint.setComplaintTypeCode(request.header().complaintTypeCode());
        complaint.setPriorityCode(request.header().priorityCode());
        complaint.setFailureLocationCode(request.header().failureLocationCode());
        complaint.setComplaintOwnerId(request.header().complaintOwnerId());
        complaint.setCoordinatorId(request.header().coordinatorId());
        complaint.setVerificationOwnerId(request.header().verificationOwnerId());
        complaint.setReportOwnerId(request.header().reportOwnerId());
        complaint.setStartDate(startDate);
        complaint.setTargetDate(targetDate);
        complaint.setCustomerTargetDate(request.header().customerTargetDate());
        complaint.setCustomerReferenceId(request.header().customerReferenceId());
        complaintMapper.insert(complaint);

        qualityPartnerMapper.insert(toEntity(request.qualityPartner(), complaintId));
        productInfoMapper.insert(toEntity(request.product(), complaintId));
        failureDescriptionMapper.insert(toEntity(request.failureDescription(), complaintId));

        List<String> sampleIds = new ArrayList<>();
        for (ComplaintRequests.Sample sample : nullToEmpty(request.samples())) {
            String sampleId = documentNumberService.nextSampleId();
            sampleMapper.insert(toEntity(sample, complaintId, sampleId));
            sampleIds.add(sampleId);
        }

        auditLogService.record(AuditActions.CREATE, "Complaint", complaintId,
                "登记投诉：" + complaintId + "，阶段 " + STAGE_FORM_TEAM + "，状态 " + STATUS_REGISTERED
                        + "，样品 " + sampleIds.size() + " 件");

        return new ComplaintResponses.Created(
                complaintId, STATUS_REGISTERED, STAGE_FORM_TEAM, startDate, targetDate,
                request.header().customerTargetDate(), sampleIds);
    }

    /** Priority -> target days, in a stable order for the wizard's date preview. */
    public List<ComplaintResponses.PriorityRule> priorityRules() {
        return priorityProperties.getTargetDays().entrySet().stream()
                .map(e -> new ComplaintResponses.PriorityRule(e.getKey(), e.getValue()))
                .sorted(Comparator.comparing(ComplaintResponses.PriorityRule::days))
                .toList();
    }

    @Transactional(readOnly = true)
    public ComplaintResponses.Detail getDetail(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }

        QualityPartner qualityPartner = qualityPartnerMapper.selectById(complaintId);
        ProductInfo product = productInfoMapper.selectById(complaintId);
        FailureDescription failureDescription = failureDescriptionMapper.selectById(complaintId);
        List<Sample> samples = sampleMapper.selectList(
                Wrappers.<Sample>lambdaQuery().eq(Sample::getComplaintId, complaintId)
                        .orderByAsc(Sample::getSampleId));

        ComplaintLabels labels = complaintMapper.findLabels(complaintId);

        return new ComplaintResponses.Detail(
                complaint.getComplaintId(),
                complaint.getStatusCode(),
                complaint.getCurrentStage(),
                complaint.getProcessType(),
                complaint.getStartDate(),
                complaint.getTargetDate(),
                complaint.getCustomerTargetDate(),
                complaint.getCloseDate(),
                complaint.getIsValid(),
                complaint.getCloseReasonCode(),
                complaint.getCustomerReferenceId(),
                complaint.getCreatedBy(),
                complaint.getCreatedAt(),
                overdueDays(complaint),
                toDto(complaint),
                toDto(qualityPartner),
                toDto(product),
                toDto(failureDescription),
                samples.stream().map(this::toDetail).toList(),
                labels);
    }

    /**
     * The complaint ledger (requirement 3.1.1): filtered, sorted and paged.
     *
     * <p>{@code scope=mine} applies the shared "related to me" predicate
     * ({@code complaint_related}), the same one the home dashboard counts with. The
     * two tab counters are unfiltered totals, matching the prototype, so they do not
     * move when a search is applied.
     */
    @Transactional(readOnly = true)
    public ComplaintResponses.LedgerPage listLedger(ComplaintRequests.LedgerQuery query) {
        int page = (query.page() == null || query.page() < 1) ? 1 : query.page();
        int size = (query.size() != null && LEDGER_PAGE_SIZES.contains(query.size()))
                ? query.size()
                : LEDGER_DEFAULT_PAGE_SIZE;

        Page<ComplaintResponses.LedgerRow> paged = newLedgerPage(page, size);
        List<ComplaintResponses.LedgerRow> items = findLedgerRows(paged, query);
        String me = CurrentUserContext.employeeId();

        return new ComplaintResponses.LedgerPage(
                items,
                paged.getTotal(),
                page,
                size,
                complaintMapper.countLedger(me, true),
                complaintMapper.countLedger(me, false));
    }

    /**
     * The same query as a workbook (requirement 3.1.1's export; the requirement
     * files this under 3.10). Paging is dropped and a ceiling applied, so an
     * unfiltered export cannot try to render the whole table.
     *
     * <p>Writable transaction, unlike the read above: the export is an audited
     * action, and an audit row cannot be inserted on a read-only connection.
     */
    @Transactional
    public byte[] exportLedger(ComplaintRequests.LedgerQuery query) {
        Page<ComplaintResponses.LedgerRow> paged = newLedgerPage(1, LEDGER_EXPORT_MAX_ROWS);
        paged.setSearchCount(false);
        List<ComplaintResponses.LedgerRow> rows = findLedgerRows(paged, query);

        auditLogService.record(AuditActions.EXPORT, "Complaint", null,
                "导出投诉台账：" + describeLedgerQuery(query) + "，共 " + rows.size() + " 行");

        return ledgerExcelWriter.toWorkbook(rows);
    }

    private Page<ComplaintResponses.LedgerRow> newLedgerPage(int page, int size) {
        // Count by wrapping the query in a subquery rather than letting MyBatis-Plus
        // rewrite it: the select list holds a function call and the ORDER BY holds
        // expressions, which is the shape that rewrite mis-handles.
        Page<ComplaintResponses.LedgerRow> paged = new Page<>(page, size);
        paged.setOptimizeCountSql(false);
        paged.setOptimizeJoinOfCountSql(false);
        return paged;
    }

    private List<ComplaintResponses.LedgerRow> findLedgerRows(Page<ComplaintResponses.LedgerRow> paged,
                                                             ComplaintRequests.LedgerQuery query) {
        return complaintMapper.findLedger(
                paged,
                CurrentUserContext.employeeId(),
                "mine".equalsIgnoreCase(query.scope()),
                blankToNull(query.q()),
                blankToNull(query.status()),
                blankToNull(query.priority()),
                blankToNull(query.customer()),
                blankToNull(query.complaintType()),
                blankToNull(query.owner()),
                blankToNull(query.product()),
                query.startFrom(),
                query.startTo(),
                query.targetFrom(),
                query.targetTo(),
                Boolean.TRUE.equals(query.overdue()),
                Boolean.TRUE.equals(query.open()),
                Boolean.TRUE.equals(query.valid()),
                blankToNull(query.sort()),
                !"asc".equalsIgnoreCase(query.order()),
                query.ids());
    }

    /** One line naming what was exported, for the audit trail. */
    private static String describeLedgerQuery(ComplaintRequests.LedgerQuery query) {
        List<String> parts = new ArrayList<>();
        if ("mine".equalsIgnoreCase(query.scope())) {
            parts.add("仅与我相关");
        }
        if (query.ids() != null && !query.ids().isEmpty()) {
            parts.add("选中 " + query.ids().size() + " 条");
        }
        if (query.q() != null && !query.q().isBlank()) {
            parts.add("关键词 " + query.q());
        }
        if (query.status() != null && !query.status().isBlank()) {
            parts.add("状态 " + query.status());
        }
        if (query.priority() != null && !query.priority().isBlank()) {
            parts.add("优先级 " + query.priority());
        }
        if (Boolean.TRUE.equals(query.overdue())) {
            parts.add("仅超期");
        }
        if (Boolean.TRUE.equals(query.open())) {
            parts.add("仅未结案");
        }
        return parts.isEmpty() ? "全部条件" : String.join("，", parts);
    }

    /**
     * How many complaints the current user is related to. The home page's card and
     * the ledger's "与我相关" tab must show the same number, so both come through
     * complaint_related rather than two similar-looking predicates.
     */
    @Transactional(readOnly = true)
    public long countRelatedToMe() {
        return complaintMapper.countLedger(CurrentUserContext.employeeId(), true);
    }

    /** 0 when on time or already closed; otherwise the days past the target date. */
    private long overdueDays(Complaint complaint) {        if (complaint.getCloseDate() != null) {
            return 0;
        }
        LocalDate target = complaint.getTargetDate();
        if (target == null) {
            return 0;
        }
        long days = ChronoUnit.DAYS.between(target, LocalDate.now());
        return Math.max(0, days);
    }

    private LocalDate resolveStartDate(ComplaintRequests.Header header) {
        if (header.startDate() != null) {
            return header.startDate();
        }
        return LocalDate.now().plusDays(START_DATE_OFFSET_DAYS);
    }

    private LocalDate resolveTargetDate(ComplaintRequests.Header header, LocalDate startDate) {
        if (header.targetDate() != null) {
            return header.targetDate();
        }
        return startDate.plusDays(priorityProperties.targetDaysFor(header.priorityCode()));
    }

    // ------------------------------------------------------------------ validation

    /**
     * Collects every problem before failing, so the user sees all of them at once
     * instead of fixing one field per round trip.
     */
    private void validateReferences(ComplaintRequests.Create request) {
        List<String> errors = new ArrayList<>();

        Set<String> dictionaryCodes = new LinkedHashSet<>();
        addIfPresent(dictionaryCodes, request.header().complaintTypeCode());
        addIfPresent(dictionaryCodes, request.header().priorityCode());
        addIfPresent(dictionaryCodes, request.header().failureLocationCode());
        addIfPresent(dictionaryCodes, request.qualityPartner().subSegmentCode());
        addIfPresent(dictionaryCodes, request.product().productTypeCode());
        addIfPresent(dictionaryCodes, request.product().packingTypeCode());
        addIfPresent(dictionaryCodes, request.failureDescription().customerFailureModeCode());
        if (!dictionaryCodes.isEmpty()) {
            Set<String> found = new HashSet<>(referenceMapper.findActiveDictionaryCodes(dictionaryCodes));
            for (String code : dictionaryCodes) {
                if (!found.contains(code)) {
                    errors.add("主数据编码不存在或已停用：" + code);
                }
            }
        }

        Set<String> employeeIds = new LinkedHashSet<>();
        addIfPresent(employeeIds, request.header().complaintOwnerId());
        addIfPresent(employeeIds, request.header().coordinatorId());
        addIfPresent(employeeIds, request.header().verificationOwnerId());
        addIfPresent(employeeIds, request.header().reportOwnerId());
        if (!employeeIds.isEmpty()) {
            Set<String> found = new HashSet<>(referenceMapper.findActiveEmployeeIds(employeeIds));
            for (String id : employeeIds) {
                if (!found.contains(id)) {
                    errors.add("人员不存在或已停用：" + id);
                }
            }
        }

        String customerCode = request.qualityPartner().qualityPartnerCode();
        boolean customerExists = referenceMapper.countCustomer(customerCode) > 0;
        if (!customerExists) {
            errors.add("质量合作伙伴不存在或已停用：" + customerCode);
        }

        // Only meaningful once the customer is known to exist.
        if (customerExists) {
            String contactId = request.qualityPartner().contactPersonId();
            if (referenceMapper.countContactOfCustomer(contactId, customerCode) == 0) {
                errors.add("联系人不属于所选质量合作伙伴：" + contactId);
            }
            String shipTo = request.qualityPartner().shipToSoldToCode();
            if (shipTo != null && !shipTo.isBlank()
                    && referenceMapper.countShipToOfCustomer(shipTo, customerCode) == 0) {
                errors.add("收货/售达方不属于所选质量合作伙伴：" + shipTo);
            }
        }

        String materialCode = request.product().materialCode();
        if (materialCode != null && !materialCode.isBlank()
                && referenceMapper.countProduct(materialCode) == 0) {
            errors.add("产品物料编码不存在或已停用：" + materialCode);
        }

        failureTypeChainValidator.validate(request.samples(), errors);

        LocalDate start = request.header().startDate();
        LocalDate target = request.header().targetDate();
        if (start != null && target != null && target.isBefore(start)) {
            errors.add("目标日期不能早于开始日期");
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    // ------------------------------------------------------------------ mapping

    private QualityPartner toEntity(ComplaintRequests.QualityPartner dto, String complaintId) {
        QualityPartner entity = new QualityPartner();
        entity.setComplaintId(complaintId);
        entity.setQualityPartnerCode(dto.qualityPartnerCode());
        entity.setApplication(dto.application());
        entity.setContactPersonId(dto.contactPersonId());
        entity.setHsCode(dto.hsCode());
        entity.setEndCustomer(dto.endCustomer());
        entity.setEccn(dto.eccn());
        entity.setSubSegmentCode(dto.subSegmentCode());
        entity.setShipToSoldToCode(dto.shipToSoldToCode());
        return entity;
    }

    private ProductInfo toEntity(ComplaintRequests.Product dto, String complaintId) {
        ProductInfo entity = new ProductInfo();
        entity.setComplaintId(complaintId);
        entity.setMaterialCode(dto.materialCode());
        entity.setProductTypeCode(dto.productTypeCode());
        entity.setPackingTypeCode(dto.packingTypeCode());
        entity.setBusinessGroup(dto.businessGroup());
        entity.setBusinessUnit(dto.businessUnit());
        entity.setNc9(dto.nc9());
        entity.setMag(dto.mag());
        entity.setCustomerPartNo(dto.customerPartNo());
        entity.setTg4(dto.tg4());
        entity.setTg5(dto.tg5());
        entity.setTg6(dto.tg6());
        entity.setProductStatus(dto.productStatus());
        entity.setIsProtected(dto.isProtected());
        return entity;
    }

    private FailureDescription toEntity(ComplaintRequests.FailureDescription dto, String complaintId) {
        FailureDescription entity = new FailureDescription();
        entity.setComplaintId(complaintId);
        entity.setCustomerFailureDescription(dto.customerFailureDescription());
        entity.setCustomerFailureModeCode(dto.customerFailureModeCode());
        entity.setD0SymptomsDescription(dto.d0SymptomsDescription());
        entity.setComment(dto.comment());
        entity.setQuantityFailing(dto.quantityFailing());
        entity.setQuantityFailingUom(dto.quantityFailingUom());
        entity.setQualityReturned(dto.qualityReturned());
        entity.setQualityReturnedUom(dto.qualityReturnedUom());
        entity.setCustomerPo(dto.customerPo());
        entity.setSalesOrder(dto.salesOrder());
        entity.setSupplierInvoiceNumber(dto.supplierInvoiceNumber());
        entity.setShippedDirectly(dto.shippedDirectly());
        entity.setDirectCommunication(dto.directCommunication());
        entity.setReceivedApprPack(dto.receivedApprPack());
        entity.setAnalysisConclusion(dto.analysisConclusion());
        return entity;
    }

    private Sample toEntity(ComplaintRequests.Sample dto, String complaintId, String sampleId) {
        return SampleSupport.newEntity(dto, complaintId, sampleId);
    }

    private ComplaintRequests.Header toDto(Complaint complaint) {
        return new ComplaintRequests.Header(
                complaint.getComplaintTypeCode(),
                complaint.getPriorityCode(),
                complaint.getFailureLocationCode(),
                complaint.getComplaintOwnerId(),
                complaint.getCoordinatorId(),
                complaint.getVerificationOwnerId(),
                complaint.getReportOwnerId(),
                complaint.getCustomerTargetDate(),
                complaint.getStartDate(),
                complaint.getTargetDate(),
                complaint.getCustomerReferenceId());
    }

    private ComplaintRequests.QualityPartner toDto(QualityPartner entity) {
        if (entity == null) {
            return null;
        }
        return new ComplaintRequests.QualityPartner(
                entity.getQualityPartnerCode(),
                entity.getApplication(),
                entity.getContactPersonId(),
                entity.getHsCode(),
                entity.getEndCustomer(),
                entity.getEccn(),
                entity.getSubSegmentCode(),
                entity.getShipToSoldToCode());
    }

    private ComplaintRequests.Product toDto(ProductInfo entity) {
        if (entity == null) {
            return null;
        }
        return new ComplaintRequests.Product(
                entity.getMaterialCode(),
                entity.getProductTypeCode(),
                entity.getPackingTypeCode(),
                entity.getBusinessGroup(),
                entity.getBusinessUnit(),
                entity.getNc9(),
                entity.getMag(),
                entity.getCustomerPartNo(),
                entity.getTg4(),
                entity.getTg5(),
                entity.getTg6(),
                entity.getProductStatus(),
                entity.getIsProtected());
    }

    private ComplaintRequests.FailureDescription toDto(FailureDescription entity) {
        if (entity == null) {
            return null;
        }
        return new ComplaintRequests.FailureDescription(
                entity.getCustomerFailureDescription(),
                entity.getCustomerFailureModeCode(),
                entity.getD0SymptomsDescription(),
                entity.getComment(),
                entity.getQuantityFailing(),
                entity.getQuantityFailingUom(),
                entity.getQualityReturned(),
                entity.getQualityReturnedUom(),
                entity.getCustomerPo(),
                entity.getSalesOrder(),
                entity.getSupplierInvoiceNumber(),
                entity.getShippedDirectly(),
                entity.getDirectCommunication(),
                entity.getReceivedApprPack(),
                entity.getAnalysisConclusion());
    }

    private ComplaintResponses.SampleDetail toDetail(Sample entity) {
        return new ComplaintResponses.SampleDetail(entity.getSampleId(), SampleSupport.toForm(entity));
    }

    // ------------------------------------------------------------------ helpers

    /** Treats "   " as absent, so a blank filter never becomes an ILIKE '%%'. */
    private static String blankToNull(String value) {
        return (value == null || value.isBlank()) ? null : value;
    }

    private static void addIfPresent(Collection<String> target, String value) {
        if (value != null && !value.isBlank()) {
            target.add(value);
        }
    }

    private static <T> List<T> nullToEmpty(List<T> list) {
        return list == null ? List.of() : list;
    }
}
