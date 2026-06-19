# Security Findings

## Summary
PointFocus's backend is security-conscious: the CGEventTap is `listenOnly` and discards every keystroke except Tab, no keystroke text is captured or logged, the single `.public` log interpolation carries only a non-sensitive tap-creation error, and no user data flows into any shell/URL/Process sink. The only material weaknesses are in `build.sh`'s certificate provisioning. No critical or high issues.

## Findings

### F-security-001: Long-lived (10-year) self-signed signing key persists in login keychain with codesign ACL
- **Severity:** medium
- **Confidence:** 70
- **Files:** build.sh:27-50
- **What:** The script generates RSA-2048 + a 3650-day self-signed leaf, imports it into `login.keychain-db` with `-T /usr/bin/codesign`, and never removes it. The private key lives in the session-unlocked login keychain for a decade. The `-T /usr/bin/codesign` ACL lets any invocation of `/usr/bin/codesign` by the user reuse this key non-interactively. Trust narrowing from the prior commit (`-r trustAsRoot -p codeSign`) is sound — it trusts only this leaf for code signing, not as a CA anchor — but the key's 10-year lifetime plus session-wide codesign ACL make it a standing local-signing oracle.
- **Why it matters:** Another process running as the user could drive `codesign` against this identity to produce binaries the machine treats as validly locally-signed. The decade validity maximizes the window.
- **Suggested fix:** Shorten validity (e.g. `-days 825`); document revocation (the `security delete-identity` hint already exists). Optionally use a dedicated keychain rather than a reusable non-interactive codesign ACL.
- **Verification:** `grep -n "days 3650" build.sh`; after a build, `security find-certificate -c "PointFocus Local Sign" -p ~/Library/Keychains/login.keychain-db | openssl x509 -noout -enddate`.

### F-security-002: EXIT-trap quoting + failure path leaves a trusted identity installed with no rollback
- **Severity:** medium
- **Confidence:** 55
- **Files:** build.sh:24-25, 47-67
- **What:** `WORK=$(mktemp -d)` then `trap "rm -rf '$WORK'" EXIT`. Two issues: (1) the trap is a double-quoted string with `$WORK` expanded at registration and wrapped in single quotes — if `TMPDIR` (attacker-influenceable) ever yields a path containing a single quote, the trap breaks quoting and `rm -rf` could hit an unintended path; (2) the `import` and `add-trusted-cert` run BEFORE the codesign-visibility check, so an early `exit 1` leaves a fully-imported, fully-trusted signing identity in the keychain while the trap only deletes the temp files.
- **Why it matters:** A crafted `TMPDIR` could redirect the cleanup `rm -rf`; and a failed provisioning run silently leaves a trusted code-signing identity the user is unlikely to notice or revoke.
- **Suggested fix:** Use `trap 'rm -rf "$WORK"' EXIT` (single-quote the trap body so `$WORK` expands at trap time, double-quoted inside) and sanity-check `$WORK` is non-empty before deletion; on the failure branch, roll back via `security delete-identity`, or move import/trust AFTER the visibility check.
- **Verification:** `grep -n "trap" build.sh`; inspect the failure branch for a keychain rollback.

### F-security-003: Input Monitoring tap reads the keycode of every system-wide keystroke though only Tab is needed
- **Severity:** medium
- **Confidence:** 45
- **Files:** Sources/PointFocus/Services/EventTapService.swift:29-33, 96-100, 121-129
- **What:** The mask requests system-wide `keyDown` and the callback reads `event.getIntegerValueField(.keyboardEventKeycode)` on every keyDown before discarding all but keycode 48. The data is never stored, logged, or transmitted (no `keyboardGetUnicodeString` anywhere) — so this is NOT a leak today; it is a latent capability where any future change adding logging/buffering inside this callback would instantly become a keylogger.
- **Why it matters:** The tap is `listenOnly` and discards immediately, so present risk is low; locking the "never log keycodes" invariant reduces the latent blast radius (OWASP collect-the-minimum).
- **Suggested fix:** Add an explicit invariant comment at the keycode-read site ("keycode must never be logged/persisted").
- **Verification:** `grep -rn "getIntegerValueField\|keyboardGetUnicodeString\|PFLog" Sources/PointFocus/Services/EventTapService.swift`.

## Out of scope
- PFLog `.public` interpolation (FocusRouter.swift:49) carries only a `TapError`/Cocoa error, never user data. Sub-medium.
- UserDefaults at rest (`com.avb.pointfocus.v1`) stores bundle IDs + 0–1 focus points; bundle IDs aren't secrets, used only as Swift dict keys (no shell/URL/SQL sink). `FocusPoint.init` clamps to [0,1]. Low.
- SMAppService.mainApp uses modern API, no privileged helper. Low.
- No hardcoded secrets in any in-scope source; PKCS12 passphrase correctly uses `openssl rand -hex 16` via file descriptor (verified vs commit a30c725).
- Entitlements/Info.plist live in Resources/ (out of target scope) — TCC scope (Accessibility + Input Monitoring) is genuinely required, not over-broad.
