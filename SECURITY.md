# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Phlox controls a Mac remotely and runs a local HTTP control server, so security
reports are taken seriously. If you believe you have found a vulnerability,
report it privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
— the **"Report a vulnerability"** button under this repository's **Security**
tab.

Please include:

- a description of the vulnerability and its impact,
- steps to reproduce (a proof of concept if possible),
- the affected version or commit.

Your report will be acknowledged, investigated, and a fix and disclosure
timeline coordinated with you. Please allow a reasonable window to address the
issue before any public disclosure.

## Scope

Phlox pairs a phone to a Mac over a private overlay network (e.g. Tailscale) and
treats the mobile token as full remote-control authority over the Mac. Reports
about token handling, the local control server, the QR pairing flow, and the
mobile-to-Mac trust boundary are especially welcome.
