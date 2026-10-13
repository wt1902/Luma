# Third-party software

Luma links the following Swift Package Manager dependencies at build time:

- Martin 3.2.4 by Tigase, Inc. — AGPL-3.0.
- MartinOMEMO 2.2.3 by Tigase, Inc. — GPL-3.0.
- WebRTC M150 binary package by the WebRTC project/stasel — BSD-style license.
- OpenSSL 3.x binary XCFramework package by krzyzanowskim — Apache-2.0. Used for
  the TLS layer (TLS 1.3, STARTTLS) and SCRAM channel binding
  (tls-exporter / tls-server-end-point).
- tigase-logging.swift, pulled transitively by Martin — AGPL-3.0.
- Tigase's libsignal Swift package, pulled by MartinOMEMO — GPL-3.0.

No third-party source code is vendored in this archive. Xcode resolves the
packages from their upstream repositories. The three direct package versions
are pinned exactly in `project.yml`; each resolved package includes its
upstream license text.
