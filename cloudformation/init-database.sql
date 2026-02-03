-- Aurora MySQL Blue/Green Test Database Schema
-- Run this after cluster deployment

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create test_data table for Blue/Green testing
CREATE TABLE IF NOT EXISTS test_data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    data_key VARCHAR(255) NOT NULL,
    data_value TEXT,
    version INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_data_key (data_key)
);

-- Create connection_log table for tracking connections during switchover
CREATE TABLE IF NOT EXISTS connection_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    connection_id VARCHAR(255),
    server_id VARCHAR(255),
    aurora_version VARCHAR(50),
    is_writer BOOLEAN,
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('Test User 1', 'user1@test.com'),
    ('Test User 2', 'user2@test.com'),
    ('Test User 3', 'user3@test.com');

INSERT INTO test_data (data_key, data_value) VALUES
    ('config_version', '1.0.0'),
    ('test_key_1', 'test_value_1'),
    ('test_key_2', 'test_value_2');

-- Show tables
SHOW TABLES;
SELECT COUNT(*) as user_count FROM users;
SELECT COUNT(*) as test_data_count FROM test_data;
