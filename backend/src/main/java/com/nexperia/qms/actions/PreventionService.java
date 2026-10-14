package com.nexperia.qms.actions;

import com.nexperia.qms.actions.dto.ActionDtos;
import com.nexperia.qms.actions.mapper.PreventionFileUpdateMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * D7 prevention of recurrence (requirement 3.8): the list of documents that must be
 * updated so the failure cannot come back -- FMEA, Control Plan, OCAP, SOP, Update
 * on Flow -- and their completion.
 *
 * Every file being complete is a precondition for entering D8, which is why the
 * outstanding count is exposed: the report stage checks it.
 */
@Service
public class PreventionService {

    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D7 = "D7";

    /** D7 sits in the complaint's "report drafting" status: the paperwork stage. */
    private static final String STATUS_REPORTING = "COMPLAINT_S06";

    private final PreventionFileUpdateMapper preventionMapper;
    private final ComplaintMapper complaintMapper;
    private final ReferenceMapper referenceMapper;
    private final AuditLogService auditLogService;

    public PreventionService(PreventionFileUpdateMapper preventionMapper,
                             ComplaintMapper complaintMapper,
                             ReferenceMapper referenceMapper,
                             AuditLogService auditLogService) {
        this.preventionMapper = preventionMapper;
        this.complaintMapper = complaintMapper;
        this.referenceMapper = referenceMapper;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<ActionDtos.PreventionView> list(String complaintId) {
        requireComplaint(complaintId);
        return preventionMapper.findByComplaint(complaintId).stream().map(this::toView).toList();
    }

    @Transactional
    public List<ActionDtos.PreventionView> create(String complaintId,
                                                  ActionDtos.PreventionRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        validate(request);

        PreventionFileUpdate entity = new PreventionFileUpdate();
        entity.setComplaintId(complaintId);
        applyRequest(entity, request);
        if (entity.getStatusCode() == null) {
            entity.setStatusCode(PreventionStatus.DEFAULT);
        }
        preventionMapper.insert(entity);

        advanceComplaint(complaint, STAGE_D7, "登记 D7 预防文件更新："
                + request.fileTypeCode());

        auditLogService.record(AuditActions.CREATE, "PreventionFileUpdate", complaintId,
                "登记 D7 预防文件更新：" + request.fileTypeCode()
                        + (request.referenceNumber() == null ? "" : "，参考编号 " + request.referenceNumber()));
        return list(complaintId);
    }

    @Transactional
    public List<ActionDtos.PreventionView> update(long updateId, ActionDtos.PreventionRequest request) {
        PreventionFileUpdate entity = requireFile(updateId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);
        validate(request);

        String previousStatus = entity.getStatusCode();
        applyRequest(entity, request);
        if (entity.getStatusCode() == null) {
            entity.setStatusCode(previousStatus);
        }
        preventionMapper.updateById(entity);

        if (!Objects.equals(previousStatus, entity.getStatusCode())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "PreventionFileUpdate",
                    entity.getComplaintId(), previousStatus, entity.getStatusCode());
        } else {
            auditLogService.record(AuditActions.UPDATE, "PreventionFileUpdate",
                    entity.getComplaintId(), "修改 D7 预防文件更新：" + updateId);
        }
        return list(entity.getComplaintId());
    }

    @Transactional
    public List<ActionDtos.PreventionView> remove(long updateId) {
        PreventionFileUpdate entity = requireFile(updateId);
        Complaint complaint = requireComplaint(entity.getComplaintId());
        requireOpen(complaint);

        preventionMapper.deleteById(updateId);
        auditLogService.record(AuditActions.DELETE, "PreventionFileUpdate",
                entity.getComplaintId(), "删除 D7 预防文件更新：" + updateId);
        return list(entity.getComplaintId());
    }

    /** Files still open; the D8 stage refuses to start while this is above zero. */
    @Transactional(readOnly = true)
    public int outstandingCount(String complaintId) {
        return preventionMapper.countOutstanding(complaintId);
    }

    // ------------------------------------------------------------------ helpers

    private void validate(ActionDtos.PreventionRequest request) {
        List<String> errors = new ArrayList<>();

        Set<String> codes = new LinkedHashSet<>();
        if (request.fileTypeCode() != null && !request.fileTypeCode().isBlank()) {
            codes.add(request.fileTypeCode());
        }
        if (!codes.isEmpty()
                && referenceMapper.findActiveDictionaryCodes(codes).size() != codes.size()) {
            errors.add("文件类型不存在或已停用：" + request.fileTypeCode());
        }

        if (request.statusCode() != null && !request.statusCode().isBlank()
                && !PreventionStatus.isKnown(request.statusCode())) {
            errors.add("预防文件状态无效：" + request.statusCode());
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    private void applyRequest(PreventionFileUpdate entity, ActionDtos.PreventionRequest request) {
        entity.setFileTypeCode(request.fileTypeCode());
        entity.setNexSampleNumber(blankToNull(request.nexSampleNumber()));
        entity.setCustomerSampleId(blankToNull(request.customerSampleId()));
        entity.setControlProgram(blankToNull(request.controlProgram()));
        entity.setReferenceNumber(blankToNull(request.referenceNumber()));
        if (request.statusCode() != null && !request.statusCode().isBlank()) {
            entity.setStatusCode(request.statusCode());
        }
    }

    private ActionDtos.PreventionView toView(PreventionFileUpdateMapper.PreventionRow row) {
        return new ActionDtos.PreventionView(
                row.updateId(), row.complaintId(), row.nexSampleNumber(), row.customerSampleId(),
                row.fileTypeCode(), row.fileTypeName(), row.controlProgram(), row.referenceNumber(),
                row.statusCode(), row.statusName(), row.createdBy(), row.createdByName(), row.createdAt());
    }

    private void advanceComplaint(Complaint complaint, String targetStage, String detail) {
        boolean stageForward = stageIndex(targetStage) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(STATUS_REPORTING) > statusOrder(complaint.getStatusCode());
        if (!stageForward && !statusForward) {
            return;
        }
        if (stageForward) {
            complaint.setCurrentStage(targetStage);
        }
        if (statusForward) {
            complaint.setStatusCode(STATUS_REPORTING);
        }
        complaintMapper.updateById(complaint);
        auditLogService.record(AuditActions.STATUS_CHANGE, "Complaint",
                complaint.getComplaintId(), detail);
    }

    private Complaint requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
        return complaint;
    }

    private PreventionFileUpdate requireFile(long updateId) {
        PreventionFileUpdate entity = preventionMapper.selectById(updateId);
        if (entity == null) {
            throw new NotFoundException("预防文件更新记录不存在：" + updateId);
        }
        return entity;
    }

    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续修改预防措施");
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
