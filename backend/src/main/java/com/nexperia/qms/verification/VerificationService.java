package com.nexperia.qms.verification;

import com.baomidou.mybatisplus.core.toolkit.Wrappers;
import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.FailureTypeChainValidator;
import com.nexperia.qms.complaint.FailureDescription;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.FailureDescriptionMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.complaint.mapper.SampleMapper;
import com.nexperia.qms.common.security.CurrentUserContext;
import com.nexperia.qms.verification.dto.VerificationDtos;
import com.nexperia.qms.verification.mapper.VerificationResultMapper;
import com.nexperia.qms.verification.mapper.VerificationTaskMapper;
import org.springframework.security.access.AccessDeniedException;
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
 * D2: verification and problem definition (requirement 3.3), including the
 * validity conclusion that decides whether the complaint continues or closes.
 *
 * The complaint's status and stage are advanced from here rather than by the
 * caller, so the two never drift apart. Advancement only ever moves forward:
 * a task created late must not drag a complaint that has already reached D5 back
 * to D2.
 */
@Service
public class VerificationService {

    /** 8D stage order, used to decide whether a move is forward. */
    private static final List<String> STAGE_ORDER =
            List.of("D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8");

    private static final String STAGE_D2 = "D2";
    private static final String STAGE_D3 = "D3";
    private static final String STAGE_CLOSED = "D8";

    /** Seeded complaint status codes; see V1 baseline and V4. */
    private static final String STATUS_SCHEDULED = "COMPLAINT_S02";
    private static final String STATUS_VERIFYING = "COMPLAINT_S03";
    private static final String STATUS_ANALYSING = "COMPLAINT_S04";
    private static final String STATUS_CLOSED = "COMPLAINT_S07";

    private static final String CLOSE_REASON_INVALID = "CLOSE_INVALID";

    /** Held by the administrator role only; gates overriding a decided verdict. */
    private static final String ADMIN_PERMISSION = "admin.all";

    private static final String MODE_MANUAL = "MANUAL";
    private static final String ENTRY_SINGLE = "SINGLE";
    private static final String ENTRY_BATCH = "BATCH";

    private final VerificationTaskMapper taskMapper;
    private final VerificationResultMapper resultMapper;
    private final ComplaintMapper complaintMapper;
    private final SampleMapper sampleMapper;
    private final FailureDescriptionMapper failureDescriptionMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;
    private final FailureTypeChainValidator failureTypeChainValidator;

    public VerificationService(VerificationTaskMapper taskMapper,
                               VerificationResultMapper resultMapper,
                               ComplaintMapper complaintMapper,
                               SampleMapper sampleMapper,
                               FailureDescriptionMapper failureDescriptionMapper,
                               ReferenceMapper referenceMapper,
                               DocumentNumberService documentNumberService,
                               AuditLogService auditLogService,
                               FailureTypeChainValidator failureTypeChainValidator) {
        this.taskMapper = taskMapper;
        this.resultMapper = resultMapper;
        this.complaintMapper = complaintMapper;
        this.sampleMapper = sampleMapper;
        this.failureDescriptionMapper = failureDescriptionMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
        this.failureTypeChainValidator = failureTypeChainValidator;
    }

    // ------------------------------------------------------------------ tasks

    @Transactional(readOnly = true)
    public List<VerificationDtos.TaskView> listTasks(String complaintId) {
        Complaint complaint = requireComplaint(complaintId);
        return taskMapper.findByComplaint(complaintId).stream()
                .map(row -> toView(row, complaint))
                .toList();
    }

    @Transactional(readOnly = true)
    public VerificationDtos.TaskDetail getTask(String taskId) {
        VerificationTask task = requireTask(taskId);
        Complaint complaint = requireComplaint(task.getComplaintId());
        List<VerificationDtos.ResultView> results = resultMapper.findByTask(taskId).stream()
                .map(r -> new VerificationDtos.ResultView(
                        r.resultId(), r.taskId(), r.testItem(),
                        r.failureTypeL1Code(), r.failureTypeL1Name(),
                        r.failureTypeL2Code(), r.failureTypeL2Name(),
                        r.failureTypeL3Code(), r.failureTypeL3Name(),
                        r.resultConclusion(), r.entryMode(),
                        r.recordedBy(), r.recordedByName(), r.recordedAt()))
                .toList();
        return new VerificationDtos.TaskDetail(toView(taskMapper.findRow(taskId), complaint), results);
    }

    @Transactional
    public VerificationDtos.TaskDetail createTask(String complaintId, VerificationDtos.TaskRequest request) {
        Complaint complaint = requireComplaint(complaintId);
        requireOpen(complaint);
        validateTask(request, complaint, null);

        String taskId = documentNumberService.nextVerificationTaskId();
        VerificationTask task = new VerificationTask();
        task.setTaskId(taskId);
        task.setComplaintId(complaintId);
        task.setCreationMode(MODE_MANUAL);
        applyRequest(task, request);
        if (task.getTaskStatus() == null) {
            // A task with a planned start is already scheduled; otherwise it waits.
            task.setTaskStatus(task.getPlannedStartDate() == null
                    ? VerificationTaskStatus.TODO : VerificationTaskStatus.SCHEDULED);
        }
        applyCompletionStamp(task, null);
        taskMapper.insert(task);

        auditLogService.record(AuditActions.CREATE, "VerificationTask", complaintId,
                "创建验证任务：" + taskId + "，负责人 " + request.taskOwnerId()
                        + "，目标完成 " + request.targetCompletionDate());

        // Verification work beginning is what moves the complaint into D2.
        advanceComplaint(complaint, STAGE_D2, STATUS_SCHEDULED,
                "创建验证任务：" + taskId + "，负责人 " + request.taskOwnerId());

        return getTask(taskId);
    }

    @Transactional
    public VerificationDtos.TaskDetail updateTask(String taskId, VerificationDtos.TaskRequest request) {
        VerificationTask task = requireTask(taskId);
        Complaint complaint = requireComplaint(task.getComplaintId());
        requireOpen(complaint);
        validateTask(request, complaint, taskId);

        String previousStatus = task.getTaskStatus();
        applyRequest(task, request);
        if (task.getTaskStatus() == null) {
            task.setTaskStatus(previousStatus);
        }
        applyCompletionStamp(task, previousStatus);
        taskMapper.updateById(task);

        if (!Objects.equals(previousStatus, task.getTaskStatus())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "VerificationTask",
                    complaint.getComplaintId(), previousStatus, task.getTaskStatus());
        } else {
            auditLogService.record(AuditActions.UPDATE, "VerificationTask",
                    complaint.getComplaintId(), "修改验证任务：" + taskId);
        }
        return getTask(taskId);
    }

    @Transactional
    public void removeTask(String taskId) {
        VerificationTask task = requireTask(taskId);
        Complaint complaint = requireComplaint(task.getComplaintId());
        requireOpen(complaint);

        taskMapper.deleteById(taskId);
        auditLogService.record(AuditActions.DELETE, "VerificationTask",
                complaint.getComplaintId(), "删除验证任务：" + taskId);
    }

    // ------------------------------------------------------------------ results

    /**
     * Records one test line (requirement 3.3, "record individually"). The failure
     * type chain is validated with the same rule registration uses.
     */
    @Transactional
    public VerificationDtos.TaskDetail addResult(String taskId, VerificationDtos.ResultRequest request) {
        return addResults(taskId, List.of(request), ENTRY_SINGLE);
    }

    /** Batch summary entry: one transaction, so a bad row cannot half-apply. */
    @Transactional
    public VerificationDtos.TaskDetail addBatchResults(String taskId,
                                                      List<VerificationDtos.ResultRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            throw new IllegalArgumentException("请至少录入一条验证结果");
        }
        return addResults(taskId, requests, ENTRY_BATCH);
    }

    private VerificationDtos.TaskDetail addResults(String taskId,
                                                   List<VerificationDtos.ResultRequest> requests,
                                                   String entryMode) {
        VerificationTask task = requireTask(taskId);
        Complaint complaint = requireComplaint(task.getComplaintId());
        requireOpen(complaint);
        if (VerificationTaskStatus.isClosedForEntry(task.getTaskStatus())) {
            throw new IllegalStateException(
                    "任务状态为「" + task.getTaskStatus() + "」，不能继续录入结果");
        }

        List<String> errors = new ArrayList<>();
        List<FailureTypeChainValidator.Codes> triples = new ArrayList<>();
        for (VerificationDtos.ResultRequest request : requests) {
            triples.add(new FailureTypeChainValidator.Codes(
                    request.failureTypeL1Code(), request.failureTypeL2Code(), request.failureTypeL3Code()));
        }
        failureTypeChainValidator.validateTriples(triples, errors);
        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }

        String operator = CurrentUserContext.employeeId();
        OffsetDateTime now = OffsetDateTime.now();
        for (VerificationDtos.ResultRequest request : requests) {
            VerificationResult result = new VerificationResult();
            result.setTaskId(taskId);
            result.setTestItem(request.testItem());
            result.setFailureTypeL1Code(blankToNull(request.failureTypeL1Code()));
            result.setFailureTypeL2Code(blankToNull(request.failureTypeL2Code()));
            result.setFailureTypeL3Code(blankToNull(request.failureTypeL3Code()));
            result.setResultConclusion(request.resultConclusion());
            result.setEntryMode(entryMode);
            result.setRecordedBy(operator);
            result.setRecordedAt(now);
            resultMapper.insert(result);
        }

        // Recorded explicitly, not only through the stage advance below: once the
        // complaint is already "verifying" that advance is a no-op, and the entry
        // must still leave a trail.
        auditLogService.record(AuditActions.CREATE, "VerificationResult", complaint.getComplaintId(),
                "录入 " + requests.size() + " 条验证结果（"
                        + (ENTRY_BATCH.equals(entryMode) ? "批量" : "逐个") + "）于任务 " + taskId);

        // Verifying is what moves the complaint from "scheduled" to "verifying".
        advanceComplaint(complaint, STAGE_D2, STATUS_VERIFYING,
                "录入验证结果于任务 " + taskId);

        return getTask(taskId);
    }

    @Transactional
    public VerificationDtos.TaskDetail removeResult(String taskId, long resultId) {
        VerificationTask task = requireTask(taskId);
        Complaint complaint = requireComplaint(task.getComplaintId());
        requireOpen(complaint);

        VerificationResult result = resultMapper.selectById(resultId);
        if (result == null || !taskId.equals(result.getTaskId())) {
            throw new NotFoundException("验证结果不属于该任务：" + resultId);
        }
        resultMapper.deleteById(resultId);
        auditLogService.record(AuditActions.DELETE, "VerificationResult",
                complaint.getComplaintId(), "删除验证结果：" + resultId + "（任务 " + taskId + "）");
        return getTask(taskId);
    }

    // ------------------------------------------------------------------ validity

    /**
     * Records the D2 conclusion.
     *
     * valid=true  -> the complaint moves on to D3.
     * valid=false -> the complaint closes immediately, which is the branch the
     *                requirement describes as "not valid, close directly".
     *
     * A conclusion already given may only be changed by an administrator
     * (confirmed with the business on 2026-10-13). Changing it is a real state
     * transition in both directions: reversing an invalid verdict reopens the
     * complaint, and reversing a valid one closes it.
     */
    @Transactional
    public VerificationDtos.ValidityResult setValidity(String complaintId,
                                                       VerificationDtos.ValidityRequest request) {
        Complaint complaint = requireComplaint(complaintId);

        Boolean previous = complaint.getIsValid();
        boolean isChange = previous != null;
        if (isChange) {
            requireAdministrator();
        }

        String reasonCode = blankToNull(request.reasonCode());
        if (!request.valid()) {
            if (reasonCode == null) {
                reasonCode = CLOSE_REASON_INVALID;
            }
            if (!"CLOSE_INVALID".equals(reasonCode)) {
                throw new IllegalArgumentException("判定为无效时，结案原因应为「投诉不成立」");
            }
        }

        complaint.setIsValid(request.valid());
        if (request.valid()) {
            if (Boolean.FALSE.equals(previous)) {
                // Reversing an invalid verdict reopens a complaint that was closed:
                // the close date and reason must go, and the stage has to move back
                // to D3. This is the one place a backward stage move is intended.
                //
                // An explicit update, not updateById: MyBatis-Plus skips null fields
                // on update, so clearing the close date would be silently dropped and
                // the complaint would look reopened in the response while staying
                // closed in the database.
                complaint.setCloseDate(null);
                complaint.setCloseReasonCode(null);
                complaint.setCurrentStage(STAGE_D3);
                complaint.setStatusCode(STATUS_ANALYSING);
                complaintMapper.update(null, Wrappers.<Complaint>lambdaUpdate()
                        .eq(Complaint::getComplaintId, complaintId)
                        .set(Complaint::getCloseDate, null)
                        .set(Complaint::getCloseReasonCode, null)
                        .set(Complaint::getCurrentStage, STAGE_D3)
                        .set(Complaint::getStatusCode, STATUS_ANALYSING)
                        .set(Complaint::getUpdatedBy, CurrentUserContext.employeeId()));
            } else {
                advanceComplaint(complaint, STAGE_D3, STATUS_ANALYSING, null);
            }
        } else {
            complaint.setCurrentStage(STAGE_CLOSED);
            complaint.setStatusCode(STATUS_CLOSED);
            complaint.setCloseReasonCode(reasonCode);
            if (complaint.getCloseDate() == null) {
                complaint.setCloseDate(LocalDate.now());
            }
            complaintMapper.updateById(complaint);
        }

        // Keep the conclusion on the failure description, which is where the form
        // collects it and where the 8D report reads it from.
        FailureDescription description = failureDescriptionMapper.selectById(complaintId);
        if (description != null && request.conclusion() != null && !request.conclusion().isBlank()) {
            description.setAnalysisConclusion(request.conclusion());
            failureDescriptionMapper.updateById(description);
        }

        String detail = "D2 有效性判定：" + (request.valid() ? "有效" : "无效")
                + (reasonCode == null ? "" : "，结案原因 " + reasonCode)
                + (request.conclusion() == null ? "" : "，结论 " + request.conclusion());
        if (isChange) {
            // A changed verdict is an override, so the before and after are both kept.
            auditLogService.recordValueChange(AuditActions.UPDATE, "Complaint", complaintId,
                    "有效性 " + (previous ? "有效" : "无效"), detail);
        } else {
            auditLogService.record(AuditActions.UPDATE, "Complaint", complaintId, detail);
        }

        return new VerificationDtos.ValidityResult(
                complaintId, request.valid(), complaint.getStatusCode(),
                complaint.getCurrentStage(), complaint.getCloseDate(),
                complaint.getCloseReasonCode());
    }

    /** A determined verdict is an administrator-level override. */
    private void requireAdministrator() {
        var user = CurrentUserContext.get();
        if (user == null || !user.can(ADMIN_PERMISSION)) {
            throw new AccessDeniedException(
                    "该投诉的有效性已判定，只有管理员可以修改");
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Moves the complaint forward only: each field advances on its own, and a
     * late task must not pull a complaint that already reached D5 back to D2.
     */
    private void advanceComplaint(Complaint complaint, String targetStage, String targetStatus, String detail) {
        boolean stageForward = stageIndex(targetStage) > stageIndex(complaint.getCurrentStage());
        boolean statusForward = statusOrder(targetStatus) > statusOrder(complaint.getStatusCode());

        if (!stageForward && !statusForward) {
            return;
        }
        if (stageForward) {
            complaint.setCurrentStage(targetStage);
        }
        if (statusForward) {
            complaint.setStatusCode(targetStatus);
        }
        complaintMapper.updateById(complaint);

        if (detail != null) {
            auditLogService.record(AuditActions.STATUS_CHANGE, "Complaint",
                    complaint.getComplaintId(), detail);
        }
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

    private int stageIndex(String stage) {
        int index = STAGE_ORDER.indexOf(stage);
        return index < 0 ? -1 : index;
    }

    private void validateTask(VerificationDtos.TaskRequest request, Complaint complaint, String excludeTaskId) {
        List<String> errors = new ArrayList<>();

        Set<String> people = new HashSet<>();
        people.add(request.taskOwnerId());
        people.removeIf(Objects::isNull);
        if (!people.isEmpty()
                && referenceMapper.findActiveEmployeeIds(people).isEmpty()) {
            errors.add("任务负责人不存在或已停用：" + request.taskOwnerId());
        }

        String sampleId = blankToNull(request.sampleId());
        if (sampleId != null && sampleMapper.countSampleOfComplaint(sampleId, complaint.getComplaintId()) == 0) {
            errors.add("样品不属于该投诉单：" + sampleId);
        }

        if (request.plannedStartDate() != null
                && request.targetCompletionDate() != null
                && request.targetCompletionDate().isBefore(request.plannedStartDate())) {
            errors.add("目标完成日期不能早于计划开始日期");
        }

        if (request.taskStatus() != null && !request.taskStatus().isBlank()
                && !VerificationTaskStatus.isKnown(request.taskStatus())) {
            errors.add("任务状态无效：" + request.taskStatus());
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    /** Stamps the completion time when the task reaches a terminal status. */
    private void applyCompletionStamp(VerificationTask task, String previousStatus) {
        boolean nowTerminal = VerificationTaskStatus.isClosedForEntry(task.getTaskStatus());
        boolean wasTerminal = VerificationTaskStatus.isClosedForEntry(previousStatus);
        if (nowTerminal && !wasTerminal) {
            task.setCompletedAt(OffsetDateTime.now());
        } else if (!nowTerminal && wasTerminal) {
            task.setCompletedAt(null);
        }
    }

    private void applyRequest(VerificationTask task, VerificationDtos.TaskRequest request) {
        task.setSampleId(blankToNull(request.sampleId()));
        task.setTaskOwnerId(request.taskOwnerId());
        task.setPlannedStartDate(request.plannedStartDate());
        task.setTargetCompletionDate(request.targetCompletionDate());
        if (request.taskStatus() != null && !request.taskStatus().isBlank()) {
            task.setTaskStatus(request.taskStatus());
        }
    }

    private VerificationDtos.TaskView toView(VerificationTaskMapper.VerificationTaskRow row, Complaint complaint) {
        if (row == null) {
            throw new NotFoundException("验证任务不存在");
        }
        return new VerificationDtos.TaskView(
                row.taskId(), row.complaintId(), row.sampleId(), row.sampleCustomerSampleId(),
                row.taskOwnerId(), row.taskOwnerName(), row.plannedStartDate(),
                row.targetCompletionDate(), row.creationMode(), row.taskStatus(),
                row.taskStatusName(), row.completedAt(),
                row.resultCount() == null ? 0 : row.resultCount(),
                targetWarning(row.targetCompletionDate(), complaint.getTargetDate()));
    }

    /**
     * Requirement 3.3: flag when the task's target falls after the complaint's, so
     * the owner sees the conflict while planning rather than at the deadline.
     */
    private String targetWarning(LocalDate taskTarget, LocalDate complaintTarget) {
        if (taskTarget == null || complaintTarget == null) {
            return null;
        }
        return taskTarget.isAfter(complaintTarget)
                ? "任务目标完成日期（" + taskTarget + "）晚于投诉目标日期（" + complaintTarget + "）"
                : null;
    }

    private Complaint requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
        return complaint;
    }

    private VerificationTask requireTask(String taskId) {
        VerificationTask task = taskMapper.selectById(taskId);
        if (task == null) {
            throw new NotFoundException("验证任务不存在：" + taskId);
        }
        return task;
    }

    /** A closed complaint is a record, not a working document. */
    private void requireOpen(Complaint complaint) {
        if (complaint.getCloseDate() != null) {
            throw new IllegalStateException("投诉单已结案，不能继续修改验证信息");
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
