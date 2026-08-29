package com.pipelinepilot.demo.api;

import com.pipelinepilot.demo.model.Order;
import com.pipelinepilot.demo.model.OrderRequest;
import com.pipelinepilot.demo.service.OrderService;
import io.micrometer.core.annotation.Timed;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @Timed(value = "pipeline_pilot_orders_create_seconds", description = "Time spent on POST /orders")
    @PostMapping("/orders")
    @ResponseStatus(HttpStatus.CREATED)
    public Order createOrder(@Valid @RequestBody OrderRequest request) {
        return orderService.createOrder(request);
    }

    @Timed(value = "pipeline_pilot_orders_list_seconds", description = "Time spent on GET /orders")
    @GetMapping("/orders")
    public List<Order> orders() {
        return orderService.getOrders();
    }
}
