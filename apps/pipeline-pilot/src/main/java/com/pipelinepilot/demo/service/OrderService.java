package com.pipelinepilot.demo.service;

import com.pipelinepilot.demo.model.Order;
import com.pipelinepilot.demo.model.OrderRequest;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class OrderService {

    private final AtomicLong idGenerator = new AtomicLong(1);
    private final CopyOnWriteArrayList<Order> orders = new CopyOnWriteArrayList<>();

    public Order createOrder(OrderRequest request) {
        Order created = new Order(
                idGenerator.getAndIncrement(),
                request.userId(),
                request.item(),
                request.quantity(),
                Instant.now()
        );
        orders.add(created);
        return created;
    }

    public List<Order> getOrders() {
        return new ArrayList<>(orders);
    }
}
