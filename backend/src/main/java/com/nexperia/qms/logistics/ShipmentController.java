package com.nexperia.qms.logistics;

import com.nexperia.qms.logistics.dto.LogisticsDtos;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Sample logistics (requirement 3.2). A batch is created against a complaint, and
 * samples are moved into it from the complaint's sample pool.
 */
@RestController
@RequestMapping("/api")
public class ShipmentController {

    /** Logistics is part of complaint handling, so editing the complaint also allows it. */
    private static final String MAY_EDIT = "hasAnyAuthority('sample:edit','complaint:edit')";

    private final ShipmentService shipmentService;

    public ShipmentController(ShipmentService shipmentService) {
        this.shipmentService = shipmentService;
    }

    @GetMapping("/complaints/{complaintId}/shipments")
    @PreAuthorize("hasAuthority('complaint:view')")
    public List<LogisticsDtos.ShipmentView> list(@PathVariable String complaintId) {
        return shipmentService.listByComplaint(complaintId);
    }

    @PostMapping("/complaints/{complaintId}/shipments")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize(MAY_EDIT)
    public LogisticsDtos.ShipmentDetail create(@PathVariable String complaintId,
                                              @Valid @RequestBody LogisticsDtos.ShipmentRequest request) {
        return shipmentService.create(complaintId, request);
    }

    @GetMapping("/shipments/{shipmentId}")
    @PreAuthorize("hasAuthority('complaint:view')")
    public LogisticsDtos.ShipmentDetail detail(@PathVariable String shipmentId) {
        return shipmentService.getDetail(shipmentId);
    }

    @PutMapping("/shipments/{shipmentId}")
    @PreAuthorize(MAY_EDIT)
    public LogisticsDtos.ShipmentDetail update(@PathVariable String shipmentId,
                                              @Valid @RequestBody LogisticsDtos.ShipmentRequest request) {
        return shipmentService.update(shipmentId, request);
    }

    @DeleteMapping("/shipments/{shipmentId}")
    @PreAuthorize(MAY_EDIT)
    public void remove(@PathVariable String shipmentId) {
        shipmentService.remove(shipmentId);
    }

    /** Moves samples from the complaint's pool into this batch (add samples to the shipment). */
    @PostMapping("/shipments/{shipmentId}/samples")
    @PreAuthorize(MAY_EDIT)
    public LogisticsDtos.ShipmentDetail addSamples(
            @PathVariable String shipmentId,
            @Valid @RequestBody List<LogisticsDtos.ShipmentSampleRequest> requests) {
        return shipmentService.addSamples(shipmentId, requests);
    }

    @DeleteMapping("/shipments/{shipmentId}/samples/{sampleId}")
    @PreAuthorize(MAY_EDIT)
    public LogisticsDtos.ShipmentDetail removeSample(@PathVariable String shipmentId,
                                                     @PathVariable String sampleId) {
        return shipmentService.removeSample(shipmentId, sampleId);
    }
}
