package com.nexperia.qms.home;

import com.nexperia.qms.home.dto.HomeDtos;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The home page's data (requirement 3.0). One call returns the figures, the
 * to-do list and the overdue banner, so the page renders in a single round trip.
 */
@RestController
@RequestMapping("/api/home")
public class HomeController {

    private final HomeService homeService;

    public HomeController(HomeService homeService) {
        this.homeService = homeService;
    }

    @GetMapping("/overview")
    @PreAuthorize("hasAuthority('complaint:view')")
    public HomeDtos.HomeOverview overview() {
        return homeService.overview();
    }
}
