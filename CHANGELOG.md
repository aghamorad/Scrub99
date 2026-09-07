# Scrub99 0.3.0

This release adds a phantom application audit for residue left behind after an application is removed.

- Checks user Application Support, Preferences, HTTP storage, Saved Application State, Group Containers, Caches, Logs, and LaunchAgents.
- Compares candidate namespaces with installed application bundles and bundle identifiers.
- Excludes Apple-owned, Scrub99, and known shared/system namespaces.
- Labels likely remnants with their exact path, measured size, reason, and review warning.
- Keeps persistent data, preferences, web storage, and launch agents review-only.
- Keeps low-risk orphan caches and logs compatible with the existing reversible quarantine workflow.
- Repairs the Xcode project’s invalid configuration-list references.

The distributed build is ad-hoc signed for local Apple-silicon use on macOS 13 or later. It is not notarized.
