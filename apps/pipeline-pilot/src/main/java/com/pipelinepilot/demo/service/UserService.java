package com.pipelinepilot.demo.service;

import com.pipelinepilot.demo.model.User;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class UserService {

    private final List<User> users = List.of(
            new User(1L, "Ada Lovelace", "ada@pipeline-pilot.local"),
            new User(2L, "Linus Torvalds", "linus@pipeline-pilot.local"),
            new User(3L, "Grace Hopper", "grace@pipeline-pilot.local")
    );

    public List<User> getUsers() {
        return users;
    }
}
