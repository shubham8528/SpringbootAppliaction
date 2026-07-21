# Remediation Summary
## Total Findings: 5
## Applied: 2
## Skipped — due to this breaking: 0
## Skipped — see Residual Risks: 3
## Breakdown by Severity:
### Critical: 2
### High: 2
### Medium: 1
### Low: 0
## Headline Outcome: Build verified: mvn compile test-compile passed

# Changes Made
* VULN-001 — `src/main/java/com/owasp/lab/service/UserService.java`: replaced raw concatenation with a parameterised native query bound via :username.
* VULN-002 — `src/main/java/com/owasp/lab/service/UserService.java`: replaced plaintext password comparison with a constant-time BCrypt match.

# Changes That Remained — Due To Build Breakage
None

# Files Referenced
* `src/main/java/com/owasp/lab/service/UserService.java`: replaced raw concatenation with a parameterised native query bound via :username and replaced plaintext password comparison with a constant-time BCrypt match.

# Vulnerability Remediations
### VULN-001 — SQL Injection in Login Functionality
* **Severity:** Critical
* **CWE / OWASP:** CWE-89 / A03:2021 - Injection
* **Status:** Applied
* **File Modified:** `src/main/java/com/owasp/lab/service/UserService.java`
* **Build Impact:** none — build remained green after this edit

#### 1. Original Vulnerable Code
<<END>>


> **Build verified: mvn compile test-compile passed** (recorded by the workflow after the agent emitted an empty patch set, or after patches applied cleanly).
