# SECURITY_ASSESSMENT_REPORT

## Executive Summary

The OWASP Vulnerability Lab is a Spring Boot application intentionally designed to be insecure for educational purposes. This report summarizes the findings of a comprehensive static application security review of the entire codebase.

**Methodology:**

* Analyzed all Java source files under `src/main/`
* Analyzed `pom.xml` for dependency and configuration risks
* Analyzed `src/main/resources/application*.{yml,yaml,properties}` for misconfiguration
* Identified security vulnerabilities, insecure coding practices, OWASP Top 10 issues, sensitive data exposure, dependency risks, broken authentication/authorization, insecure API implementations, and configuration weaknesses

**Top-line Risk Posture:**

* High-risk vulnerabilities: 5
* Medium-risk vulnerabilities: 10
* Low-risk vulnerabilities: 5

**Total Findings by Severity:**

* Critical: 2
* High: 5
* Medium: 10
* Low: 5

## Risk Matrix

| Severity | Likelihood | Count |
| --- | --- | --- |
| Critical | High | 2 |
| High | Medium | 5 |
| Medium | Low | 10 |
| Low | Low | 5 |

## Vulnerability Findings

### VULN-001: SQL Injection (High)

* **Vulnerability Name:** SQL Injection
* **CWE ID:** CWE-89
* **OWASP Top 10 Category:** A03:2021 - Injection
* **Severity:** High
* **Affected File:** `src/main/java/com/owasp/lab/service/UserService.java`
* **Affected Method/Class:** `findByUsernameUnsafe`
* **Exact Vulnerable Code Snippet:**
