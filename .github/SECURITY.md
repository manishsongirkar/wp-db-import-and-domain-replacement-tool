# Security Policy

## 🛡️ Supported Versions

We actively maintain and provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | ✅ Yes             |
| < Latest| ❌ No              |

## 🚨 Reporting a Vulnerability

If you discover a security vulnerability in the WordPress Database Import & Domain Replacement Tool, please report it responsibly:

### 📧 Contact Information

- **Email:** [Create an issue with the security label]
- **Response Time:** We aim to respond within 48 hours
- **Resolution Time:** Security issues are prioritized and typically resolved within 7 days

### 🔒 What to Include

When reporting a security vulnerability, please include:

1. **Description** - Clear description of the vulnerability
2. **Impact** - Potential impact and severity
3. **Steps to Reproduce** - Detailed reproduction steps
4. **Environment** - OS, Bash version, and other relevant details
5. **Proof of Concept** - If applicable (without causing harm)

### 🛠️ Vulnerability Types We Take Seriously

- **Command Injection** - Improper input sanitization
- **Path Traversal** - Directory traversal vulnerabilities
- **Code Execution** - Arbitrary code execution risks
- **SQL Injection** - Database security issues
- **Information Disclosure** - Exposure of sensitive data
- **Privilege Escalation** - Unauthorized access elevation

### ✅ Security Best Practices

This tool follows security best practices:

- ✅ **Input Validation** - All user inputs are sanitized
- ✅ **Path Safety** - Uses absolute paths to prevent traversal
- ✅ **SQL Safety** - Uses WP-CLI for database operations
- ✅ **Temporary Files** - Process-specific temporary file naming
- ✅ **Error Handling** - Comprehensive error management

### 🔄 Security Update Process

1. **Assessment** - We evaluate the reported vulnerability
2. **Fix Development** - Security fix is developed and tested
3. **Release** - Fix is released as a security update
4. **Notification** - Security advisory is published
5. **Credit** - Reporter is credited (if desired)

### 🙏 Responsible Disclosure

We appreciate responsible disclosure and will:

- Acknowledge your report within 48 hours
- Provide regular updates on our progress
- Credit you in our security advisory (if desired)
- Work with you to ensure the vulnerability is properly addressed

Thank you for helping keep the WordPress Database Import Tool secure! 🛡️
