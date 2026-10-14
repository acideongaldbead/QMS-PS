package com.nexperia.qms.rootcause;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.rootcause.dto.RootCauseDtos;
import com.nexperia.qms.rootcause.mapper.RootCauseMapper;
import com.nexperia.qms.rootcause.mapper.WhyAnalysisMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * D4 root-cause analysis (requirement 3.5): the root-cause entries themselves plus
 * the 3x5Why and fishbone content attached to each.
 *
 * Analysis content is append-only per version, so saving never destroys what was
 * there before -- the requirement asks for version history on the online editors
 * and that falls out of the storage shape.
 */
@Service
public class RootCauseService {

    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D4 = "D4";

    /** D3 and D4 both sit in the complaint's "analysing" status. */
    private static final String STATUS_ANALYSING = "COMPLAINT_S04";

    public static final String TYPE_WHY = "3x5WHY";
    public static final String TYPE_FISHBONE = "FISHBONE";

    private final RootCauseMapper rootCauseMapper;
    private final WhyAnalysisMapper whyAnalysisMapper;
    private final ComplaintMapper complaintMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;

    public RootCauseService(RootCauseMapper rootCauseMapper,
                            WhyAnalysisMapper whyAnalysisMapper,
                            ComplaintMapper complaintMapper,
                            ReferenceMapper referenceMapper,
                            DocumentNumberService documentNumberService,
                            AuditLogService auditLogService) {
        this.rootCauseMapper = rootCauseMapper;
        this.whyAnalysisMapper = whyAnalysisMapper;
        this.complaintMapper = complaintMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<RootCauseDtos.RootCauseView> list(String complaintId) {
        requireComplaint(complaintId);
        return rootCauseMapper.findByComplaint(complaintId).stream().map(this::toView).toList();
    }

    @Transactional(readOnly = true)
    public RootCauseDtos.RootCauseDetail get(String rootCauseId) {
        RootCause entity = requireRootCause(rootCauseId);
        RootCauseDtos.RootCauseView view = toView(rootCauseMapper.findRow(rootCauseId));
        return new RootCauseDtos.RootCauseDetail(
                view,
                toAnalysisView(whyAnalysisMapper.findLatest(rootCauseId, TYPE_WHY)),
                toAnalysisView(whyAnalysisMapper.findLatest(rootCauseId, TYPE_FISHBONE)));
    }

    @Transactional
    public RootCauseDtos.RootCauseDetail create(String complaintId, RootCauseDtos.RootCauseRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        validate(request);

        String rootCauseId = documentNumberService.nextRootCauseId();
        RootCause entity = new RootCause();
        entity.setRootCauseId(rootCauseId);
        entity.setComplaintId(complaintId);
        applyRequest(entity, request);
        if (entity.getStatusCode() == null) {
            entity.setStatusCode(RootCauseStatus.DEFAULT);
        }
        rootCauseMapper.insert(entity);

        // Root-cause analysis beginning is what moves the complaint into D4.
        advanceComplaint(complaint, STAGE_D4, "创建根因条目：" + rootCauseId);

        auditLogService.record(AuditActions.CREATE, "RootCause", complaintId,
                "创建根因条目：" + rootCauseId + "，状态 " + entity.getStatusCode());
        return get(rootCauseId);
    }

    @Transactional
    public RootCauseDtos.RootCauseDetail update(String rootCauseId, RootCauseDtos.RootCauseRequest request) {
        RootCause entity = requireRootCause(rootCauseId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);
        validate(request);

        String previousStatus = entity.getStatusCode();
        applyRequest(entity, request);
        if (entity.getStatusCode() == null) {
            entity.setStatusCode(previousStatus);
        }
        rootCauseMapper.updateById(entity);

        if (!Objects.equals(previousStatus, entity.getStatusCode())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "RootCause",
                    entity.getComplaintId(), previousStatus, entity.getStatusCode());
        } else {
            auditLogService.record(AuditActions.UPDATE, "RootCause", entity.getComplaintId(),
                    "修改根因条目：" + rootCauseId);
        }
        return get(rootCauseId);
    }

    @Transactional
    public void remove(String rootCauseId) {
        RootCause entity = requireRootCause(rootCauseId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);

        rootCauseMapper.deleteById(rootCauseId);
        auditLogService.record(AuditActions.DELETE, "RootCause", entity.getComplaintId(),
                "删除根因条目：" + rootCauseId);
    }

    /**
     * Records the ownership decision and, when the cause lies outside, hands it to
     * another organisation (PS-047). The transfer time is stamped so the handover
     * is traceable.
     */
    @Transactional
    public RootCauseDtos.RootCauseDetail transfer(String rootCauseId, RootCauseDtos.TransferRequest request) {
        RootCause entity = requireRootCause(rootCauseId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);

        List<String> errors = new ArrayList<>();
        if (referenceMapper.findActiveEmployeeIds(List.of(request.transferredToId())).isEmpty()) {
            errors.add("转交对象不存在或已停用：" + request.transferredToId());
        }
        if (request.responsibleOrgCode() != null && !request.responsibleOrgCode().isBlank()
                && referenceMapper.findActiveDictionaryCodes(List.of(request.responsibleOrgCode())).isEmpty()) {
            errors.add("责任组织不存在或已停用：" + request.responsibleOrgCode());
        }
        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }

        entity.setTransferredToId(request.transferredToId());
        entity.setTransferredAt(OffsetDateTime.now());
        if (request.responsibleOrgType() != null && !request.responsibleOrgType().isBlank()) {
            entity.setResponsibleOrgType(request.responsibleOrgType());
        }
        if (request.responsibleOrgCode() != null && !request.responsibleOrgCode().isBlank()) {
            entity.setResponsibleOrgCode(request.responsibleOrgCode());
        }
        rootCauseMapper.updateById(entity);

        auditLogService.record(AuditActions.UPDATE, "RootCause", entity.getComplaintId(),
                "根因转交：" + rootCauseId + " -> " + request.transferredToId()
                        + (request.note() == null ? "" : "，说明 " + request.note()));
        return get(rootCauseId);
    }

    /**
     * Saves a new version of one tool's content.
     *
     * A version row is appended rather than updated, so the previous content is
     * never lost. Saving the first analysis also moves the root cause from "to
     * analyse" to "analysing", because that is what starting the work means.
     */
    @Transactional
    public RootCauseDtos.RootCauseDetail saveAnalysis(String rootCauseId,
                                                      RootCauseDtos.AnalysisRequest request) {
        RootCause entity = requireRootCause(rootCauseId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);

        String type = canonicalType(request.analysisType());
        if (type == null) {
            throw new IllegalArgumentException("分析类型只能是 3x5WHY 或 FISHBONE");
        }

        int nextVersion = whyAnalysisMapper.maxVersion(rootCauseId, type) + 1;
        whyAnalysisMapper.insertJson(rootCauseId, type, request.contentJson(), nextVersion,
                CurrentUserContext.employeeId());

        if (RootCauseStatus.TODO.equals(entity.getStatusCode())) {
            entity.setStatusCode(RootCauseStatus.DOING);
            rootCauseMapper.updateById(entity);
        }

        auditLogService.record(AuditActions.UPDATE, "RootCause", entity.getComplaintId(),
                "保存" + (TYPE_WHY.equals(type) ? " 3x5Why" : " 鱼骨图") + "内容，"
                        + rootCauseId + " 版本 v" + nextVersion);
        return get(rootCauseId);
    }

    @Transactional(readOnly = true)
    public List<RootCauseDtos.AnalysisView> listVersions(String rootCauseId, String analysisType) {
        requireRootCause(rootCauseId);
        return whyAnalysisMapper.findVersions(rootCauseId, canonicalType(analysisType)).stream()
                .map(this::toAnalysisView)
                .toList();
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Maps whatever casing the client sent onto the canonical constant.
     *
     * Case-insensitive comparison, NOT toUpperCase(): "3x5WHY" uppercased becomes
     * "3X5WHY", which then matches neither constant. The stored value is always the
     * canonical one, so the mapper queries comparing on '3x5WHY' stay valid.
     */
    private static String canonicalType(String raw) {
        if (raw == null) {
            return null;
        }
        if (TYPE_WHY.equalsIgnoreCase(raw)) {
            return TYPE_WHY;
        }
        if (TYPE_FISHBONE.equalsIgnoreCase(raw)) {
            return TYPE_FISHBONE;
        }
        return null;
    }

    private void validate(RootCauseDtos.RootCauseRequest request) {
        List<String> errors = new ArrayList<>();

        if (request.statusCode() != null && !request.statusCode().isBlank()
                && !RootCauseStatus.isKnown(request.statusCode())) {
            errors.add("根因状态无效：" + request.statusCode());
        }

        Set<String> orgCodes = new LinkedHashSet<>();
        if (request.responsibleOrgCode() != null && !request.responsibleOrgCode().isBlank()) {
            orgCodes.add(request.responsibleOrgCode());
        }
        if (!orgCodes.isEmpty()
                && referenceMapper.findActiveDictionaryCodes(orgCodes).size() != orgCodes.size()) {
            errors.add("责任组织不存在或已停用：" + request.responsibleOrgCode());
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    private void applyRequest(RootCause entity, RootCauseDtos.RootCauseRequest request) {
        entity.setRootCauseDesc(request.rootCauseDesc());
        entity.setRootCauseSummary(request.rootCauseSummary());
        entity.setRiskAssessment(request.riskAssessment());
        entity.setResponsibleOrgType(blankToNull(request.responsibleOrgType()));
        entity.setResponsibleOrgCode(blankToNull(request.responsibleOrgCode()));
        if (request.statusCode() != null && !request.statusCode().isBlank()) {
            entity.setStatusCode(request.statusCode());
        }
    }

    /** Forward-only, with the status following the same rule as elsewhere. */
    private void advanceComplaint(Complaint complaint, String targetStage, String detail) {
        boolean stageForward = stageIndex(targetStage) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(STATUS_ANALYSING) > statusOrder(complaint.getStatusCode());
        if (!stageForward && !statusForward) {
            return;
        }
        if (stageForward) {
            complaint.setCurrentStage(targetStage);
        }
        if (statusForward) {
            complaint.setStatusCode(STATUS_ANALYSING);
        }
        complaintMapper.updateById(complaint);
        auditLogService.record(AuditActions.STATUS_CHANGE, "Complaint",
                complaint.getComplaintId(), detail);
    }

    private RootCauseDtos.RootCauseView toView(RootCauseMapper.RootCauseRow row) {
        if (row == null) {
            throw new NotFoundException("根因条目不存在");
        }
        return new RootCauseDtos.RootCauseView(
                row.rootCauseId(), row.complaintId(), row.rootCauseDesc(),
                row.rootCauseSummary(), row.riskAssessment(),
                row.responsibleOrgType(), row.responsibleOrgCode(), row.responsibleOrgName(),
                row.transferredToId(), row.transferredToName(), row.transferredAt(),
                row.statusCode(), row.statusName(),
                row.createdBy(), row.createdByName(), row.createdAt(),
                row.whyCount() == null ? 0 : row.whyCount(),
                row.fishboneCount() == null ? 0 : row.fishboneCount());
    }

    private RootCauseDtos.AnalysisView toAnalysisView(WhyAnalysisMapper.AnalysisRow row) {
        if (row == null) {
            return null;
        }
        return new RootCauseDtos.AnalysisView(
                row.analysisId(), row.rootCauseId(), row.analysisType(),
                row.contentJson(), row.versionNo(), row.createdBy(),
                row.createdByName(), row.createdAt());
    }

    private Complaint requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
        return complaint;
    }

    private RootCause requireRootCause(String rootCauseId) {
        RootCause entity = rootCauseMapper.selectById(rootCauseId);
        if (entity == null) {
            throw new NotFoundException("根因条目不存在：" + rootCauseId);
        }
        return entity;
    }

    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续修改根因分析");
        }
    }

    private int stageIndex(String stage) {
        int index = STAGE_ORDER.indexOf(stage);
        return index < 0 ? -1 : index;
    }

    private int statusOrder(String status) {
        if (status == null) {
            return 0;
        }
        return switch (status) {
            case "COMPLAINT_S01" -> 1;
            case "COMPLAINT_S02" -> 2;
            case "COMPLAINT_S03" -> 3;
            case "COMPLAINT_S04" -> 4;
            case "COMPLAINT_S05" -> 5;
            case "COMPLAINT_S06" -> 6;
            case "COMPLAINT_S07" -> 7;
            default -> 0;
        };
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
