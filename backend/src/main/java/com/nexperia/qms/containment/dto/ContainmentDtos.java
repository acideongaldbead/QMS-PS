package com.nexperia.qms.containment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class ContainmentDtos {

    private ContainmentDtos() {
    }

    /** Create or update a D3 action. Planned action and owner are mandatory in the schema. */
    public record ActionRequest(
            @Size(max = 64) String nexSampleNumber,
            @Size(max = 64) String customerSampleNumber,
            @NotBlank(message = "计划措施不能为空") String plannedAction,
            @NotBlank(message = "责任人不能为空") String ownerId,
            /** When the action is meant to finish. */
            LocalDate plannedCompletionDate,
            /** When it actually finished; stamped automatically on completion. */
            LocalDate completedDate,
            String statusCode,
            String result) {
    }

    public record ActionView(
            String actionId,
            String complaintId,
            String nexSampleNumber,
            String customerSampleNumber,
            String plannedAction,
            String ownerId,
            String ownerName,
            LocalDate plannedCompletionDate,
            LocalDate completedDate,
            String statusCode,
            String statusName,
            String result,
            String createdBy,
            String createdByName,
            OffsetDateTime createdAt,
            /**
             * Set when the action finished before it was planned to, which is the
             * anomaly the schema's comment asks to flag. A warning, never a block.
             */
            String completionWarning) {
    }

    /**
     * The PS-039 decision. A note is required when the answer is "not required",
     * because skipping D3 has to be justified.
     */
    public record DecisionRequest(
            @NotNull(message = "请给出是否需要遏制措施的判断") Boolean required,
            String note) {
    }

    /**
     * Everything the D3 tab needs: whether containment is required at all, and the
     * actions when it is. One request rather than two, because the screen shows
     * them together.
     */
    public record ContainmentSummary(
            /** null until the decision is made. */
            Boolean required,
            String decisionNote,
            List<ActionView> actions,
            boolean complaintClosed) {
    }
}
