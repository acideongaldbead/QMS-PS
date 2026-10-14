package com.nexperia.qms.complaint.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/**
 * Registration payload, mirroring the five-step wizard and the four 1:1 blocks
 * the schema keeps separate.
 *
 * These records serve as both the write shape and the read shape: validation
 * annotations only take effect where the controller applies @Valid, so the detail
 * endpoint can reuse them without a second parallel set of DTOs.
 */
public final class ComplaintRequests {

    private ComplaintRequests() {
    }

    public record Create(
            @NotNull @Valid Header header,
            @NotNull @Valid QualityPartner qualityPartner,
            @NotNull @Valid Product product,
            @NotNull @Valid FailureDescription failureDescription,
            @Valid List<Sample> samples) {
    }

    /**
     * The complaint ledger's search form (requirement 3.1.1). Every field is
     * optional; {@code scope} is "mine" or "all" and decides whether the
     * "related to me" predicate is applied.
     *
     * <p>Parameter names must stay in step with the `<choose>` branches in
     * {@code ComplaintMapper.findLedger} - that is where the sort whitelist lives.
     */
    public record LedgerQuery(
            String scope,
            String q,
            String status,
            String priority,
            String customer,
            String complaintType,
            String owner,
            String product,
            LocalDate startFrom,
            LocalDate startTo,
            LocalDate targetFrom,
            LocalDate targetTo,
            Boolean overdue,
            Boolean open,
            Boolean valid,
            Integer page,
            Integer size,
            String sort,
            String order,
            /** Explicit ids to restrict to, set only by the export of a row selection. */
            List<String> ids) {
    }

    /**
     * Fields marked "allowed to be changed by the coordinator" in requirement
     * 3.1.2 are accepted here; the rest are owned by the flow.
     *
     * startDate and targetDate are optional: when omitted the service applies the
     * documented defaults (created + 7 days, then start + priority days).
     */
    public record Header(
            @NotBlank(message = "投诉类型不能为空") String complaintTypeCode,
            @NotBlank(message = "优先级不能为空") String priorityCode,
            @NotBlank(message = "失效位置不能为空") String failureLocationCode,
            @NotBlank(message = "投诉负责人不能为空") String complaintOwnerId,
            @NotBlank(message = "协调人不能为空") String coordinatorId,
            String verificationOwnerId,
            String reportOwnerId,
            @NotNull(message = "客户要求目标日期不能为空") LocalDate customerTargetDate,
            LocalDate startDate,
            LocalDate targetDate,
            @Size(max = 64) String customerReferenceId) {
    }

    /**
     * subSegmentCode is required because the schema has no customer -> sub-segment
     * mapping (the customer table carries name, country, city and street only), so
     * it cannot be derived and must be chosen.
     */
    public record QualityPartner(
            @NotBlank(message = "质量合作伙伴不能为空") String qualityPartnerCode,
            @NotBlank(message = "是否应用不能为空")
            @Pattern(regexp = "Yes|No", message = "是否应用只能是 Yes 或 No") String application,
            @NotBlank(message = "联系人不能为空") String contactPersonId,
            @Size(max = 32) String hsCode,
            @Size(max = 128) String endCustomer,
            @Size(max = 32) String eccn,
            @NotBlank(message = "子分部不能为空") String subSegmentCode,
            String shipToSoldToCode) {
    }

    /**
     * materialCode is optional so a complaint can still be registered when the part
     * is not yet in the product master; productTypeCode and packingTypeCode are
     * mandatory in the schema.
     */
    public record Product(
            String materialCode,
            @NotBlank(message = "产品类型不能为空") String productTypeCode,
            @NotBlank(message = "包装类型不能为空") String packingTypeCode,
            @Size(max = 32) String businessGroup,
            @Size(max = 32) String businessUnit,
            @Size(max = 32) String nc9,
            @Size(max = 32) String mag,
            @Size(max = 64) String customerPartNo,
            @Size(max = 32) String tg4,
            @Size(max = 32) String tg5,
            @Size(max = 32) String tg6,
            @Size(max = 32) String productStatus,
            Boolean isProtected) {
    }

    public record FailureDescription(
            String customerFailureDescription,
            @NotBlank(message = "客户失效模式不能为空") String customerFailureModeCode,
            String d0SymptomsDescription,
            String comment,
            @PositiveOrZero(message = "失效数量不能为负") BigDecimal quantityFailing,
            @Size(max = 8) String quantityFailingUom,
            @PositiveOrZero(message = "退回数量不能为负") BigDecimal qualityReturned,
            @Size(max = 8) String qualityReturnedUom,
            @Size(max = 32) String customerPo,
            @Size(max = 32) String salesOrder,
            @Size(max = 32) String supplierInvoiceNumber,
            Boolean shippedDirectly,
            String directCommunication,
            @Size(max = 32) String receivedApprPack,
            String analysisConclusion) {
    }

    /**
     * The three failure type codes form a chain: L2 must sit under L1 and L3 under
     * L2. The service verifies that, because a foreign key cannot.
     */
    public record Sample(
            @Size(max = 64) String customerSampleId,
            @Size(max = 32) String champId,
            @PositiveOrZero(message = "样品数量不能为负") BigDecimal sampleQuantity,
            @Size(max = 8) String uom,
            @Size(max = 255) String description,
            @Size(max = 128) String productMarking,
            @Size(max = 64) String applicationArea,
            Boolean rejectConfirmed,
            String conclusion,
            String failureTypeL1Code,
            String failureTypeL2Code,
            String failureTypeL3Code) {
    }
}
