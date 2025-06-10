---
applyTo: "**/*.ps1"
---

- Use `PascalCase` for functions and `camelCase` for variables.
- Add `#Requires -Version 7.0` when using PowerShell 7+ features.
- Begin scripts with `Set-StrictMode -Version Latest`.
- Structure logic into functions; provide a `Main` entrypoint.
- Use `param()` with `[Parameter()]` validation; avoid global variables.
- Use `try/catch` for error handling.
- Prefer `Write-Output` and `Write-Error`.
- Implement `SupportsShouldProcess` and `-WhatIf` for destructive actions.
