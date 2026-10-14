package com.nexperia.qms.actions;

import com.nexperia.qms.actions.dto.ActionDtos;
import com.nexperia.qms.actions.mapper.ActionVerificationMapper;
import com.nexperia.qms.actions.mapper.CorrectiveActionMapper;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.rootcause.RootCause;
import com.nexperia.qms.rootcause.mapper.RootCauseMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

/**
 * D5 corrective actions and their D6 implementation/effectiveness check
 * (requirements 3.6 and 3.7).
 *
 * The two live together because D6 exists only to settle D5's outcome: recording
 * an effectiveness judgement is what moves the action to verified, and recording a
 * negative one puts it back for rework (PS-053, PS-054).
 */
@Service
public class CorrectiveActionService {

    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D5 = "D5";
    private static final String STAGE_D6 = "D6";

    /** D5 and D6 both sit in the complaint's "actions in progress" status. */
    private static final String STATUS_ACTIONS = "COMPLAINT_S05";

    private final CorrectiveActionMapper actionMapper;
    private final ActionVerificationMapper verificationMapper;
    private final ComplaintMapper complaintMapper;
    private final RootCauseMapper rootCauseMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;

    public CorrectiveActionService(CorrectiveActionMapper actionMapper,
                                   ActionVerificationMapper verificationMapper,
                                   ComplaintMapper complaintMapper,
                                   RootCauseMapper rootCauseMapper,
                                   ReferenceMapper referenceMapper,
                                   DocumentNumberService documentNumberService,
                                   AuditLogService auditLogService) {
        this.actionMapper = actionMapper;
        this.verificationMapper = verificationMapper;
        this.complaintMapper = complaintMapper;
        this.rootCauseMapper = rootCauseMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<ActionDtos.CorrectiveActionView> list(String complaintId) {
        requireComplaint(complaintId);
        return actionMapper.findByComplaint(complaintId).stream().map(this::toView).toList();
    }

    @Transactional(readOnly = true)
    public ActionDtos.CorrectiveActionDetail get(String actionId) {
        CorrectiveAction action = requireAction(actionId);
        List<ActionDtos.VerificationView> verifications = verificationMapper.findByAction(actionId).stream()
                .map(v -> new ActionDtos.VerificationView(
                        v.verificationId(), v.correctiveActionId(), v.actualCompletionDate(),
                        v.verificationResult(), v.isEffective(), v.verifiedBy(),
                        v.verifiedByName(), v.verifiedAt()))
                .toList();
        return new ActionDtos.CorrectiveActionDetail(toView(actionMapper.findRow(actionId)), verifications);
    }

    @Transactional
    public ActionDtos.CorrectiveActionDetail create(String complaintId,
                                                    ActionDtos.CorrectiveActionRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        validate(request, complaintId);

        String actionId = documentNumberService.nextCorrectiveActionId();
        CorrectiveAction action = new CorrectiveAction();
        action.setCorrectiveActionId(actionId);
        action.setComplaintId(complaintId);
        applyRequest(action, request);
        if (action.getStatusCode() == null) {
            action.setStatusCode(CorrectiveStatus.DEFAULT);
        }
        actionMapper.insert(action);

        advanceComplaint(complaint, STAGE_D5, "创建纠正措施：" + actionId
                + "（根因 " + request.rootCauseId() + "）");

        auditLogService.record(AuditActions.CREATE, "CorrectiveAction", complaintId,
                "创建纠正措施：" + actionId + "，责任人 " + request.ownerId()
                        + "，目标日期 " + request.targetDate());
        return get(actionId);
    }

    @Transactional
    public ActionDtos.CorrectiveActionDetail update(String actionId,
                                                    ActionDtos.CorrectiveActionRequest request) {
        CorrectiveAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);
        validate(request, action.getComplaintId());

        String previousStatus = action.getStatusCode();
        applyRequest(action, request);
        if (action.getStatusCode() == null) {
            action.setStatusCode(previousStatus);
        }
        actionMapper.updateById(action);

        if (!Objects.equals(previousStatus, action.getStatusCode())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "CorrectiveAction",
                    action.getComplaintId(), previousStatus, action.getStatusCode());
        } else {
            auditLogService.record(AuditActions.UPDATE, "CorrectiveAction",
                    action.getComplaintId(), "修改纠正措施：" + actionId);
        }
        return get(actionId);
    }

    @Transactional
    public void remove(String actionId) {
        CorrectiveAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);

        actionMapper.deleteById(actionId);
        auditLogService.record(AuditActions.DELETE, "CorrectiveAction",
                action.getComplaintId(), "删除纠正措施：" + actionId);
    }

    // ------------------------------------------------------------------ D6

    /**
     * Records D6 feedback. The action's status follows the input: an actual
     * completion date means it is implemented, and an effectiveness judgement
     * settles it as verified or sends it back for rework.
     */
    @Transactional
    public ActionDtos.CorrectiveActionDetail addVerification(String actionId,
                                                             ActionDtos.VerificationRequest request) {
        CorrectiveAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);

        ActionVerification verification = new ActionVerification();
        verification.setCorrectiveActionId(actionId);
        verification.setActualCompletionDate(request.actualCompletionDate());
        verification.setVerificationResult(request.verificationResult());
        verification.setIsEffective(request.isEffective());
        if (request.isEffective() != null) {
            verification.setVerifiedBy(CurrentUserContext.employeeId());
            verification.setVerifiedAt(OffsetDateTime.now());
        }
        verificationMapper.insert(verification);

        String previousStatus = action.getStatusCode();
        String nextStatus = previousStatus;

        if (request.actualCompletionDate() != null
                && (CorrectiveStatus.TODO.equals(previousStatus) || CorrectiveStatus.FAILED.equals(previousStatus))) {
            nextStatus = CorrectiveStatus.DONE;
        }
        if (Boolean.TRUE.equals(request.isEffective())) {
            nextStatus = CorrectiveStatus.VERIFIED;
        } else if (Boolean.FALSE.equals(request.isEffective())) {
            // PS-054: an ineffective action goes back for rework rather than closing.
            nextStatus = CorrectiveStatus.FAILED;
        }

        if (!Objects.equals(previousStatus, nextStatus)) {
            action.setStatusCode(nextStatus);
            actionMapper.updateById(action);
        }

        advanceComplaint(complaint, STAGE_D6, "录入纠正措施验证：" + actionId);

        // A status move is logged as STATUS_CHANGE with both sides, so it can be
        // found by event type rather than read out of a free-text sentence.
        if (!Objects.equals(previousStatus, nextStatus)) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "CorrectiveAction",
                    action.getComplaintId(), previousStatus + "（" + describeEffectiveness(request.isEffective()) + "）",
                    nextStatus);
        } else {
            auditLogService.record(AuditActions.UPDATE, "CorrectiveAction", action.getComplaintId(),
                    "D6 " + actionId + " 验证结果：" + describeEffectiveness(request.isEffective()));
        }
        return get(actionId);
    }

    @Transactional
    public ActionDtos.CorrectiveActionDetail removeVerification(String actionId, long verificationId) {
        CorrectiveAction action = requireAction(actionId);
        Complaint complaint = requireComplaint(action.getComplaintId());
        requireOpen(complaint);

        ActionVerification verification = verificationMapper.selectById(verificationId);
        if (verification == null || !actionId.equals(verification.getCorrectiveActionId())) {
            throw new NotFoundException("验证记录不属于该纠正措施：" + verificationId);
        }
        verificationMapper.deleteById(verificationId);
        auditLogService.record(AuditActions.DELETE, "ActionVerification",
                action.getComplaintId(), "删除纠正措施验证记录：" + verificationId);
        return get(actionId);
    }

    private String describeEffectiveness(Boolean effective) {
        if (effective == null) {
            return "仅记录实施进展，未判定有效性";
        }
        return effective ? "有效" : "无效，返回返工";
    }

    // ------------------------------------------------------------------ helpers

    private void validate(ActionDtos.CorrectiveActionRequest request, String complaintId) {
        List<String> errors = new ArrayList<>();

        RootCause rootCause = rootCauseMapper.selectById(request.rootCauseId());
        if (rootCause == null) {
            errors.add("根因不存在：" + request.rootCauseId());
        } else if (!Objects.equals(rootCause.getComplaintId(), complaintId)) {
            // A corrective action must address a root cause of the same complaint.
            errors.add("根因不属于该投诉单：" + request.rootCauseId());
        }

        Set<String> people = new HashSet<>();
        people.add(request.ownerId());
        people.removeIf(Objects::isNull);
        if (!people.isEmpty() && referenceMapper.findActiveEmployeeIds(people).isEmpty()) {
            errors.add("责任人不存在或已停用：" + request.ownerId());
        }

        if (request.statusCode() != null && !request.statusCode().isBlank()
                && !CorrectiveStatus.isKnown(request.statusCode())) {
            errors.add("纠正措施状态无效：" + request.statusCode());
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    private void applyRequest(CorrectiveAction action, ActionDtos.CorrectiveActionRequest request) {
        action.setRootCauseId(request.rootCauseId());
        action.setNexSampleNumber(blankToNull(request.nexSampleNumber()));
        action.setCustomerSampleId(blankToNull(request.customerSampleId()));
        action.setPlannedActionDesc(request.plannedActionDesc());
        action.setOwnerId(request.ownerId());
        action.setTargetDate(request.targetDate());
        if (request.statusCode() != null && !request.statusCode().isBlank()) {
            action.setStatusCode(request.statusCode());
        }
    }

    private ActionDtos.CorrectiveActionView toView(CorrectiveActionMapper.CorrectiveActionRow row) {
        if (row == null) {
            throw new NotFoundException("纠正措施不存在");
        }
        return new ActionDtos.CorrectiveActionView(
                row.correctiveActionId(), row.rootCauseId(), row.rootCauseSummary(), row.complaintId(),
                row.nexSampleNumber(), row.customerSampleId(), row.plannedActionDesc(),
                row.ownerId(), row.ownerName(), row.targetDate(),
                row.statusCode(), row.statusName(),
                row.latestVerificationId(), row.actualCompletionDate(), row.isEffective(),
                row.verificationResult(), row.verifiedAt(), row.verifiedByName(),
                row.verificationCount() == null ? 0 : row.verificationCount());
    }

    /** Forward-only, with the status following the same rule as elsewhere. */
    private void advanceComplaint(Complaint complaint, String targetStage, String detail) {
        boolean stageForward = stageIndex(targetStage) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(STATUS_ACTIONS) > statusOrder(complaint.getStatusCode());
        if (!stageForward && !statusForward) {
            return;
        }
        if (stageForward) {
            complaint.setCurrentStage(targetStage);
        }
        if (statusForward) {
            complaint.setStatusCode(STATUS_ACTIONS);
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

    private CorrectiveAction requireAction(String actionId) {
        CorrectiveAction action = actionMapper.selectById(actionId);
        if (action == null) {
            throw new NotFoundException("纠正措施不存在：" + actionId);
        }
        return action;
    }

    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续修改纠正措施");
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
