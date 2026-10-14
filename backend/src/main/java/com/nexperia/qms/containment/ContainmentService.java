package com.nexperia.qms.containment;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.containment.dto.ContainmentDtos;
import com.nexperia.qms.containment.mapper.ContainmentActionMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * D3 containment actions (requirement 3.4) plus the PS-039 decision on whether
 * containment is needed at all.
 *
 * The decision is enforced rather than recorded and ignored: answering "not
 * required" moves the complaint to D4, and the two states cannot contradict each
 * other -- you cannot skip containment while actions are still registered, and you
 * cannot register actions after deciding to skip.
 */
@Service
public class ContainmentService {

    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D3 = "D3";
    private static final String STAGE_D4 = "D4";

    /** D3 and D4 both sit in the complaint's "analysing" status. */
    private static final String STATUS_ANALYSING = "COMPLAINT_S04";

    private final ContainmentActionMapper actionMapper;
    private final ComplaintMapper complaintMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;

    public ContainmentService(ContainmentActionMapper actionMapper,
                              ComplaintMapper complaintMapper,
                              ReferenceMapper referenceMapper,
                              DocumentNumberService documentNumberService,
                              AuditLogService auditLogService) {
        this.actionMapper = actionMapper;
        this.complaintMapper = complaintMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public ContainmentDtos.ContainmentSummary summary(String complaintId) {
        Complaint complaint = requireComplaint(complaintId);
        return new ContainmentDtos.ContainmentSummary(
                complaint.getContainmentRequired(),
                complaint.getContainmentDecisionNote(),
                actionsOf(complaintId),
                complaint.getCloseDate() != null);
    }

    @Transactional
    public ContainmentDtos.ContainmentSummary createAction(String complaintId,
                                                           ContainmentDtos.ActionRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        if (Boolean.FALSE.equals(complaint.getContainmentRequired())) {
            throw new IllegalStateException(
                    "该投诉已判定为「不需要遏制措施」，如需登记请先把判断改为需要");
        }
        validate(request);

        String actionId = documentNumberService.nextContainmentActionId();
        ContainmentAction action = new ContainmentAction();
        action.setActionId(actionId);
        action.setComplaintId(complaintId);
        applyRequest(action, request);
        if (action.getStatusCode() == null) {
            action.setStatusCode(ContainmentStatus.DEFAULT);
        }
        stampCompletion(action, null);
        actionMapper.insert(action);

        // Registering a containment action is what puts the complaint into D3 and
        // settles the PS-039 answer as "required".
        if (complaint.getContainmentRequired() == null) {
            complaint.setContainmentRequired(true);
            complaintMapper.updateById(complaint);
        }
        advanceComplaint(complaint, STAGE_D3, "登记遏制措施：" + actionId);

        auditLogService.record(AuditActions.CREATE, "ContainmentAction", complaintId,
                "登记遏制措施：" + actionId + "，责任人 " + request.ownerId());
        return summary(complaintId);
    }

    @Transactional
    public ContainmentDtos.ContainmentSummary updateAction(String actionId,
                                                            ContainmentDtos.ActionRequest request) {
        ContainmentAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);
        validate(request);

        String previousStatus = action.getStatusCode();
        applyRequest(action, request);
        if (action.getStatusCode() == null) {
            action.setStatusCode(previousStatus);
        }
        stampCompletion(action, previousStatus);
        actionMapper.updateById(action);

        if (!Objects.equals(previousStatus, action.getStatusCode())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "ContainmentAction",
                    action.getComplaintId(), previousStatus, action.getStatusCode());
        } else {
            auditLogService.record(AuditActions.UPDATE, "ContainmentAction",
                    action.getComplaintId(), "修改遏制措施：" + actionId);
        }
        return summary(action.getComplaintId());
    }

    @Transactional
    public ContainmentDtos.ContainmentSummary removeAction(String actionId) {
        ContainmentAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);

        actionMapper.deleteById(actionId);
        auditLogService.record(AuditActions.DELETE, "ContainmentAction",
                action.getComplaintId(), "删除遏制措施：" + actionId);
        return summary(action.getComplaintId());
    }

    /**
     * The PS-039 decision. Answering "not required" advances the complaint to D4;
     * answering "required" puts it back on D3.
     *
     * The stage only ever moves forward from here, so flipping the answer after the
     * complaint has moved past D4 records the decision without rewinding the stage
     * bar -- the actions themselves stay editable regardless.
     */
    @Transactional
    public ContainmentDtos.ContainmentSummary decide(String complaintId,
                                                     ContainmentDtos.DecisionRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);

        if (!request.required() && (request.note() == null || request.note().isBlank())) {
            throw new IllegalArgumentException("判定为「不需要遏制措施」时必须填写理由");
        }
        if (!request.required() && countActions(complaintId) > 0) {
            throw new IllegalStateException(
                    "该投诉已登记遏制措施，不能判定为不需要；如需跳过请先删除已登记的措施");
        }

        complaint.setContainmentRequired(request.required());
        complaint.setContainmentDecisionNote(request.note());
        complaintMapper.updateById(complaint);

        if (request.required()) {
            advanceComplaint(complaint, STAGE_D3, "判断为需要遏制措施");
        } else {
            advanceComplaint(complaint, STAGE_D4, "判断为不需要遏制措施");
        }

        auditLogService.record(AuditActions.UPDATE, "Complaint", complaintId,
                "D3 遏制判断：" + (request.required() ? "需要" : "不需要")
                        + (request.note() == null ? "" : "，理由 " + request.note()));
        return summary(complaintId);
    }

    // ------------------------------------------------------------------ helpers

    /** Moves the complaint's stage forward only, and audits the move. */
    private void advanceComplaint(Complaint complaint, String targetStage, String detail) {
        boolean forward = stageIndex(targetStage) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(STATUS_ANALYSING) > statusOrder(complaint.getStatusCode());
        if (!forward && !statusForward) {
            return;
        }
        if (forward) {
            complaint.setCurrentStage(targetStage);
        }
        if (statusForward) {
            complaint.setStatusCode(STATUS_ANALYSING);
        }
        complaintMapper.updateById(complaint);
        auditLogService.record(AuditActions.STATUS_CHANGE, "Complaint",
                complaint.getComplaintId(), detail);
    }

    private void validate(ContainmentDtos.ActionRequest request) {
        List<String> errors = new ArrayList<>();

        Set<String> people = new HashSet<>();
        people.add(request.ownerId());
        people.removeIf(Objects::isNull);
        if (!people.isEmpty() && referenceMapper.findActiveEmployeeIds(people).isEmpty()) {
            errors.add("责任人不存在或已停用：" + request.ownerId());
        }

        if (request.statusCode() != null && !request.statusCode().isBlank()
                && !ContainmentStatus.isKnown(request.statusCode())) {
            errors.add("遏制措施状态无效：" + request.statusCode());
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    /** Stamps the completion date when the action first reaches a terminal status. */
    private void stampCompletion(ContainmentAction action, String previousStatus) {
        boolean nowTerminal = ContainmentStatus.isTerminal(action.getStatusCode());
        boolean wasTerminal = ContainmentStatus.isTerminal(previousStatus);
        if (nowTerminal && !wasTerminal && action.getCompletedDate() == null) {
            action.setCompletedDate(LocalDate.now());
        }
    }

    private void applyRequest(ContainmentAction action, ContainmentDtos.ActionRequest request) {
        action.setNexSampleNumber(blankToNull(request.nexSampleNumber()));
        action.setCustomerSampleNumber(blankToNull(request.customerSampleNumber()));
        action.setPlannedAction(request.plannedAction());
        action.setOwnerId(request.ownerId());
        action.setPlannedCompletionDate(request.plannedCompletionDate());
        action.setCompletedDate(request.completedDate());
        action.setResult(request.result());
        if (request.statusCode() != null && !request.statusCode().isBlank()) {
            action.setStatusCode(request.statusCode());
        }
    }

    /**
     * The schema comment asks to flag a completion date earlier than the planned
     * date. It is a warning rather than a rejection: finishing early is suspicious
     * (a mis-keyed date, or containment that was not really carried out) but it is
     * not for the system to refuse the record.
     */
    private String completionWarning(LocalDate planned, LocalDate completed) {
        if (planned == null || completed == null) {
            return null;
        }
        return completed.isBefore(planned)
                ? "完成日期（" + completed + "）早于计划完成日期（" + planned + "）"
                : null;
    }

    private List<ContainmentDtos.ActionView> actionsOf(String complaintId) {
        return actionMapper.findByComplaint(complaintId).stream()
                .map(r -> new ContainmentDtos.ActionView(
                        r.actionId(), r.complaintId(), r.nexSampleNumber(),
                        r.customerSampleNumber(), r.plannedAction(), r.ownerId(),
                        r.ownerName(), r.plannedCompletionDate(), r.completedDate(),
                        r.statusCode(), r.statusName(),
                        r.result(), r.createdBy(), r.createdByName(), r.createdAt(),
                        completionWarning(r.plannedCompletionDate(), r.completedDate())))
                .toList();
    }

    private long countActions(String complaintId) {
        return actionMapper.findByComplaint(complaintId).size();
    }

    private Complaint requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
        return complaint;
    }

    private ContainmentAction requireAction(String actionId) {
        ContainmentAction action = actionMapper.selectById(actionId);
        if (action == null) {
            throw new NotFoundException("遏制措施不存在：" + actionId);
        }
        return action;
    }

    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续修改遏制措施");
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
