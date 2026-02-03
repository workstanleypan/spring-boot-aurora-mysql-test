-- Aurora Blue/Green Test Database Initialization
-- Run this BEFORE creating Blue/Green deployment

-- Create test users (non-admin, SELECT only on mysql.*)
CREATE USER IF NOT EXISTS 'testuser1'@'%' IDENTIFIED BY 'testuser';
CREATE USER IF NOT EXISTS 'testuser2'@'%' IDENTIFIED BY 'testuser';
CREATE USER IF NOT EXISTS 'testuser3'@'%' IDENTIFIED BY 'testuser';

-- Grant SELECT on mysql.* (system tables)
GRANT SELECT ON mysql.* TO 'testuser1'@'%';
GRANT SELECT ON mysql.* TO 'testuser2'@'%';
GRANT SELECT ON mysql.* TO 'testuser3'@'%';

-- Grant usage on testdb for application testing
GRANT ALL PRIVILEGES ON testdb.* TO 'testuser1'@'%';
GRANT ALL PRIVILEGES ON testdb.* TO 'testuser2'@'%';
GRANT ALL PRIVILEGES ON testdb.* TO 'testuser3'@'%';

FLUSH PRIVILEGES;

-- Create test table
USE testdb;

CREATE TABLE IF NOT EXISTS users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS test_data (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    data_key VARCHAR(50) NOT NULL,
    data_value TEXT,
    version INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('Test User 1', 'test1@example.com'),
    ('Test User 2', 'test2@example.com')
ON DUPLICATE KEY UPDATE name=name;

-- Verify users created
SELECT User, Host FROM mysql.user WHERE User LIKE 'testuser%';
