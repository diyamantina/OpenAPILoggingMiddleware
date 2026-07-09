# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.3.x | yes |
| < 1.3 | no |

Fixes land on the latest `1.3.x` line. Please upgrade before reporting.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Use GitHub's private reporting: open the repository's **Security** tab and
choose **Report a vulnerability**. If that is unavailable, email the
maintainer at **mihaelamj@gmail.com** with:

- a description of the issue and its impact,
- steps or a minimal sample that reproduces it,
- the affected version and platform (macOS / Linux / etc.).

You can expect an acknowledgement within a few days. Once a fix is ready it
ships in a patch release and the advisory is published. Please keep details
private until a release is available.

## Scope

This is request/response logging middleware. The most relevant class of issue
is **accidental disclosure of sensitive data in logs**. The middleware
redacts a default set of sensitive headers (for example `Authorization`,
`Cookie`, `Set-Cookie`) and only captures bodies when a `BodyLoggingPolicy`
opts in. Reports about gaps in that redaction, or about ways body capture
leaks data the policy meant to exclude, are in scope.
