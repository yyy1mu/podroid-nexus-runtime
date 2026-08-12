---
name: Bug Report
about: Something isn't working as expected
title: '[Bug] '
labels: bug
assignees: ''
---

## Description
A clear and concise description of what the bug is.

## Affected release
Include the runtime tag and the Nexus app version.

## Steps to reproduce
Describe the VM start or OpenCode request that fails.

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened instead.

## Diagnostic evidence
Attach the failed GitHub Actions job log for build failures. For runtime
failures, attach the Nexus virtual-machine log and `/var/log/opencode.log`.

Also include:
```
uname -a
cat /etc/alpine-release
/usr/local/bin/opencode --version
```

## Additional Context
Add any other context about the problem here.
