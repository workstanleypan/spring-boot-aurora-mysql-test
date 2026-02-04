package com.test.service;

import com.test.model.User;
import com.test.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * User Service
 * Business logic layer
 */
@Service
public class UserService {
    
    private static final Logger log = LoggerFactory.getLogger(UserService.class);
    
    private final UserRepository userRepository;
    
    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }
    
    public List<User> getAllUsers() {
        log.info("Getting all users");
        return userRepository.findAll();
    }
    
    public User getUserById(Long id) {
        log.info("Getting user by id: {}", id);
        return userRepository.findById(id);
    }
    
    public User createUser(String name) {
        log.info("Creating user with name: {}", name);
        int rows = userRepository.insert(name);
        if (rows > 0) {
            log.info("User created successfully");
            return new User(null, name, null);
        }
        return null;
    }
    
    public boolean updateUser(Long id, String name) {
        log.info("Updating user id={} with name={}", id, name);
        int rows = userRepository.update(id, name);
        return rows > 0;
    }
    
    public boolean deleteUser(Long id) {
        log.info("Deleting user id={}", id);
        int rows = userRepository.delete(id);
        return rows > 0;
    }
    
    public long getUserCount() {
        log.info("Getting user count");
        return userRepository.count();
    }
}
