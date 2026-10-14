package com.nexperia.qms.logistics;

import com.nexperia.qms.common.audit.AuditActions;
import com.nexperia.qms.common.audit.AuditLogService;
import com.nexperia.qms.common.exception.NotFoundException;
import com.nexperia.qms.common.numbering.DocumentNumberService;
import com.nexperia.qms.complaint.Complaint;
import com.nexperia.qms.complaint.mapper.ComplaintMapper;
import com.nexperia.qms.complaint.mapper.ReferenceMapper;
import com.nexperia.qms.complaint.mapper.SampleMapper;
import com.nexperia.qms.logistics.dto.LogisticsDtos;
import com.nexperia.qms.logistics.mapper.ShipmentMapper;
import com.nexperia.qms.logistics.mapper.ShipmentSampleMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Shipments of failed parts and the samples they carry (requirements 3.2.1, 3.2.2).
 *
 * A complaint can have several batches, and a sample can travel in more than one
 * (the link table is unique on shipment + sample, not on sample alone). The rules
 * that no foreign key expresses -- samples must belong to the same complaint, and
 * cannot be added twice to one batch -- are enforced here.
 */
@Service
public class ShipmentService {

    private final ShipmentMapper shipmentMapper;
    private final ShipmentSampleMapper shipmentSampleMapper;
    private final SampleMapper sampleMapper;
    private final ComplaintMapper complaintMapper;
    private final ReferenceMapper referenceMapper;
    private final DocumentNumberService documentNumberService;
    private final AuditLogService auditLogService;

    public ShipmentService(ShipmentMapper shipmentMapper,
                           ShipmentSampleMapper shipmentSampleMapper,
                           SampleMapper sampleMapper,
                           ComplaintMapper complaintMapper,
                           ReferenceMapper referenceMapper,
                           DocumentNumberService documentNumberService,
                           AuditLogService auditLogService) {
        this.shipmentMapper = shipmentMapper;
        this.shipmentSampleMapper = shipmentSampleMapper;
        this.sampleMapper = sampleMapper;
        this.complaintMapper = complaintMapper;
        this.referenceMapper = referenceMapper;
        this.documentNumberService = documentNumberService;
        this.auditLogService = auditLogService;
    }

    @Transactional(readOnly = true)
    public List<LogisticsDtos.ShipmentView> listByComplaint(String complaintId) {
        requireComplaint(complaintId);
        return shipmentMapper.findByComplaint(complaintId).stream().map(this::toView).toList();
    }

    @Transactional(readOnly = true)
    public LogisticsDtos.ShipmentDetail getDetail(String shipmentId) {
        Shipment shipment = requireShipment(shipmentId);

        List<LogisticsDtos.ShipmentSampleView> samples = shipmentSampleMapper.findByShipment(shipmentId)
                .stream()
                .map(r -> new LogisticsDtos.ShipmentSampleView(
                        r.shipmentSampleId(), r.shipmentId(), r.sampleId(),
                        r.sampleCustomerSampleId(), r.customerSampleId(), r.description(),
                        r.dateCode(), r.dbId(), r.qty(), r.uom(), r.assemblyCenter(),
                        r.testCenter(), r.numOfDies(), r.failureTypeName()))
                .toList();

        Set<String> linked = new HashSet<>();
        for (LogisticsDtos.ShipmentSampleView sample : samples) {
            linked.add(sample.sampleId());
        }

        List<LogisticsDtos.SamplePoolItem> pool = sampleMapper
                .findRowsByComplaint(shipment.getComplaintId()).stream()
                .map(r -> new LogisticsDtos.SamplePoolItem(
                        r.sampleId(), r.customerSampleId(), r.champId(), r.description(),
                        r.quantity(), r.uom(), r.rejectConfirmed(), r.failureTypeName(),
                        linked.contains(r.sampleId())))
                .toList();

        return new LogisticsDtos.ShipmentDetail(
                toView(shipmentMapper.findRow(shipmentId)), samples, pool);
    }

    @Transactional
    public LogisticsDtos.ShipmentDetail create(String complaintId, LogisticsDtos.ShipmentRequest request) {
        requireComplaint(complaintId);
        validate(request);

        String shipmentId = documentNumberService.nextShipmentId();
        Shipment shipment = new Shipment();
        shipment.setShipmentId(shipmentId);
        shipment.setComplaintId(complaintId);
        applyRequest(shipment, request);
        shipmentMapper.insert(shipment);

        auditLogService.record(AuditActions.CREATE, "Shipment", complaintId,
                "登记物流批次：" + shipmentId + "，承运商 " + request.carrierName()
                        + "，寄送数量 " + request.quantityPartsShipped());
        return getDetail(shipmentId);
    }

    @Transactional
    public LogisticsDtos.ShipmentDetail update(String shipmentId, LogisticsDtos.ShipmentRequest request) {
        Shipment shipment = requireShipment(shipmentId);
        validate(request);

        String previousStatus = shipment.getShipmentStatus();
        LocalDate previousClose = shipment.getCloseDate();
        applyRequest(shipment, request);
        shipmentMapper.updateById(shipment);

        if (!java.util.Objects.equals(previousStatus, shipment.getShipmentStatus())
                || !java.util.Objects.equals(previousClose, shipment.getCloseDate())) {
            auditLogService.recordValueChange(AuditActions.STATUS_CHANGE, "Shipment",
                    shipment.getComplaintId(),
                    String.valueOf(previousStatus) + " / " + previousClose,
                    shipment.getShipmentStatus() + " / " + shipment.getCloseDate());
        } else {
            auditLogService.record(AuditActions.UPDATE, "Shipment", shipment.getComplaintId(),
                    "修改物流批次：" + shipmentId);
        }
        return getDetail(shipmentId);
    }

    @Transactional
    public void remove(String shipmentId) {
        Shipment shipment = requireShipment(shipmentId);
        shipmentMapper.deleteById(shipmentId);
        auditLogService.record(AuditActions.DELETE, "Shipment", shipment.getComplaintId(),
                "删除物流批次：" + shipmentId);
    }

    /**
     * Adds samples to a batch. Every problem is collected before failing, so one
     * request cannot half-apply.
     */
    @Transactional
    public LogisticsDtos.ShipmentDetail addSamples(String shipmentId,
                                                  List<LogisticsDtos.ShipmentSampleRequest> requests) {
        Shipment shipment = requireShipment(shipmentId);
        if (requests == null || requests.isEmpty()) {
            throw new IllegalArgumentException("请至少选择一个样品");
        }

        List<String> errors = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (LogisticsDtos.ShipmentSampleRequest request : requests) {
            String sampleId = request.sampleId();
            if (!seen.add(sampleId)) {
                errors.add("样品重复出现：" + sampleId);
                continue;
            }
            if (sampleMapper.countSampleOfComplaint(sampleId, shipment.getComplaintId()) == 0) {
                errors.add("样品不属于该投诉单：" + sampleId);
                continue;
            }
            if (shipmentSampleMapper.countLink(shipmentId, sampleId) > 0) {
                errors.add("样品已在该批次中：" + sampleId);
            }
        }
        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }

        for (LogisticsDtos.ShipmentSampleRequest request : requests) {
            ShipmentSample link = new ShipmentSample();
            link.setShipmentId(shipmentId);
            link.setSampleId(request.sampleId());
            link.setDescription(request.description());
            link.setDateCode(request.dateCode());
            link.setDbId(request.dbId());
            link.setQty(request.qty());
            link.setUom(request.uom());
            link.setCustomerSampleId(request.customerSampleId());
            link.setAssemblyCenter(request.assemblyCenter());
            link.setTestCenter(request.testCenter());
            link.setNumOfDies(request.numOfDies());
            shipmentSampleMapper.insert(link);
        }

        auditLogService.record(AuditActions.UPDATE, "Shipment", shipment.getComplaintId(),
                "向物流批次 " + shipmentId + " 添加 " + requests.size() + " 个样品");
        return getDetail(shipmentId);
    }

    @Transactional
    public LogisticsDtos.ShipmentDetail removeSample(String shipmentId, String sampleId) {
        Shipment shipment = requireShipment(shipmentId);
        ShipmentSample link = shipmentSampleMapper.findLink(shipmentId, sampleId);
        if (link == null) {
            throw new NotFoundException("该样品不在此物流批次中：" + sampleId);
        }
        shipmentSampleMapper.deleteById(link.getShipmentSampleId());
        auditLogService.record(AuditActions.UPDATE, "Shipment", shipment.getComplaintId(),
                "从物流批次 " + shipmentId + " 移除样品 " + sampleId);
        return getDetail(shipmentId);
    }

    // ------------------------------------------------------------------ helpers

    private void validate(LogisticsDtos.ShipmentRequest request) {
        List<String> errors = new ArrayList<>();

        Set<String> people = new LinkedHashSet<>();
        people.add(request.senderId());
        people.add(request.receiverId());
        people.removeIf(java.util.Objects::isNull);
        if (!people.isEmpty()) {
            Set<String> found = new HashSet<>(referenceMapper.findActiveEmployeeIds(people));
            for (String id : people) {
                if (!found.contains(id)) {
                    errors.add("人员不存在或已停用：" + id);
                }
            }
        }

        if (request.shipmentStatus() != null && !request.shipmentStatus().isBlank()
                && !ShipmentStatus.isKnown(request.shipmentStatus())) {
            errors.add("物流状态无效：" + request.shipmentStatus());
        }

        if (request.startDate() != null && request.targetDate() != null
                && request.targetDate().isBefore(request.startDate())) {
            errors.add("目标日期不能早于开始日期");
        }
        if (request.startDate() != null && request.closeDate() != null
                && request.closeDate().isBefore(request.startDate())) {
            errors.add("关闭日期不能早于开始日期");
        }

        if (!errors.isEmpty()) {
            throw new IllegalArgumentException(String.join("；", errors));
        }
    }

    /**
     * Copies the request onto the entity and applies the one date rule: reaching a
     * terminal status stamps the close date when it is still empty, which is what
     * "Close Date" means for a delivered or cancelled batch.
     */
    private void applyRequest(Shipment shipment, LogisticsDtos.ShipmentRequest request) {
        shipment.setSenderId(request.senderId());
        shipment.setReceiverId(request.receiverId());
        shipment.setShipmentNo(request.shipmentNo());
        shipment.setShipmentStatus(
                request.shipmentStatus() == null || request.shipmentStatus().isBlank()
                        ? (shipment.getShipmentStatus() == null ? ShipmentStatus.DEFAULT : shipment.getShipmentStatus())
                        : request.shipmentStatus());
        shipment.setQuantityPartsShipped(request.quantityPartsShipped());
        shipment.setApplication(request.application());
        shipment.setStartDate(request.startDate());
        shipment.setCarrierName(request.carrierName());
        shipment.setCarrierTrackingNumber(request.carrierTrackingNumber());
        shipment.setTargetDate(request.targetDate());
        shipment.setCloseDate(request.closeDate());
        shipment.setComments(request.comments());

        if (shipment.getCloseDate() == null && ShipmentStatus.isTerminal(shipment.getShipmentStatus())) {
            shipment.setCloseDate(LocalDate.now());
        }
    }

    private LogisticsDtos.ShipmentView toView(ShipmentMapper.ShipmentRow row) {
        if (row == null) {
            throw new NotFoundException("物流批次不存在");
        }
        return new LogisticsDtos.ShipmentView(
                row.shipmentId(), row.complaintId(), row.senderId(), row.senderName(),
                row.receiverId(), row.receiverName(), row.shipmentNo(),
                row.shipmentStatus(), row.shipmentStatusName(), row.quantityPartsShipped(),
                row.application(), row.startDate(), row.carrierName(),
                row.carrierTrackingNumber(), row.targetDate(), row.closeDate(),
                row.comments(), row.createdBy(), row.createdByName(), row.createdAt(),
                row.sampleCount() == null ? 0 : row.sampleCount(),
                overdueDays(row));
    }

    /** 0 once closed or on time; otherwise the days past the target date. */
    private long overdueDays(ShipmentMapper.ShipmentRow row) {
        if (row.closeDate() != null || row.targetDate() == null) {
            return 0;
        }
        return Math.max(0, ChronoUnit.DAYS.between(row.targetDate(), LocalDate.now()));
    }

    private void requireComplaint(String complaintId) {
        Complaint complaint = complaintMapper.selectById(complaintId);
        if (complaint == null) {
            throw new NotFoundException("投诉单不存在：" + complaintId);
        }
    }

    private Shipment requireShipment(String shipmentId) {
        Shipment shipment = shipmentMapper.selectById(shipmentId);
        if (shipment == null) {
            throw new NotFoundException("物流批次不存在：" + shipmentId);
        }
        return shipment;
    }
}
