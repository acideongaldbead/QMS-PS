package com.nexperia.qms.logistics.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class LogisticsDtos {

    private LogisticsDtos() {
    }

    /**
     * Create/update payload for a shipment (requirement 3.2.1). Sender, receiver,
     * carrier and quantity are mandatory because the schema declares them NOT NULL.
     */
    public record ShipmentRequest(
            @NotBlank(message = "寄件人不能为空") String senderId,
            @NotBlank(message = "收件人不能为空") String receiverId,
            @Size(max = 64) String shipmentNo,
            String shipmentStatus,
            @NotNull(message = "寄送数量不能为空")
            @PositiveOrZero(message = "寄送数量不能为负") BigDecimal quantityPartsShipped,
            @Pattern(regexp = "Yes|No", message = "是否应用只能是 Yes 或 No") String application,
            LocalDate startDate,
            @NotBlank(message = "承运商不能为空") @Size(max = 64) String carrierName,
            @Size(max = 64) String carrierTrackingNumber,
            LocalDate targetDate,
            LocalDate closeDate,
            String comments) {
    }

    public record ShipmentView(
            String shipmentId,
            String complaintId,
            String senderId,
            String senderName,
            String receiverId,
            String receiverName,
            String shipmentNo,
            String shipmentStatus,
            String shipmentStatusName,
            BigDecimal quantityPartsShipped,
            String application,
            LocalDate startDate,
            String carrierName,
            String carrierTrackingNumber,
            LocalDate targetDate,
            LocalDate closeDate,
            String comments,
            String createdBy,
            String createdByName,
            OffsetDateTime createdAt,
            int sampleCount,
            /** Days past the target date while still open; 0 once closed or on time. */
            long overdueDays) {
    }

    /** Per-batch sample attributes (requirement 3.2.2). */
    public record ShipmentSampleRequest(
            @NotBlank(message = "样品ID不能为空") String sampleId,
            @Size(max = 255) String description,
            @Size(max = 32) String dateCode,
            @Size(max = 32) String dbId,
            @PositiveOrZero(message = "数量不能为负") BigDecimal qty,
            @Size(max = 8) String uom,
            @Size(max = 64) String customerSampleId,
            @Size(max = 64) String assemblyCenter,
            @Size(max = 64) String testCenter,
            @PositiveOrZero(message = "芯片数不能为负") Integer numOfDies) {
    }

    public record ShipmentSampleView(
            Long shipmentSampleId,
            String shipmentId,
            String sampleId,
            String sampleCustomerSampleId,
            String customerSampleId,
            String description,
            String dateCode,
            String dbId,
            BigDecimal qty,
            String uom,
            String assemblyCenter,
            String testCenter,
            Integer numOfDies,
            String failureTypeName) {
    }

    /** A sample of the complaint, as offered by the transfer list. */
    public record SamplePoolItem(
            String sampleId,
            String customerSampleId,
            String champId,
            String description,
            BigDecimal quantity,
            String uom,
            Boolean rejectConfirmed,
            String failureTypeName,
            /** True when this sample is already in the shipment being viewed. */
            boolean inThisShipment) {
    }

    /**
     * A shipment plus everything the screen needs: what is already in it, and what
     * could be added. Returning both avoids a second round trip on every edit.
     */
    public record ShipmentDetail(
            ShipmentView shipment,
            List<ShipmentSampleView> samples,
            List<SamplePoolItem> availableSamples) {
    }
}
