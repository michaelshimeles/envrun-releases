# envrun releases

Public, immutable, signed Linux releases for envrun. The source repository is
private; this repository contains only the installer, compiled release archive,
checksums, signatures, and release metadata.

Install the latest release:

```sh
curl -fsSL https://github.com/michaelshimeles/envrun-releases/releases/latest/download/envrun-install.sh | sh
```

For a reproducible installation, use a versioned release URL and pass the same
version to the installer. The installer verifies an Ed25519 signature over the
complete release manifest, then verifies the archive before extracting anything.

The release-signing key fingerprint is:

```text
SHA256:zlZge1Zqmjg8ojDlhyLhinBU8o20xpjlb2zpbrAhDJ8
```

Published GitHub Releases are immutable: their assets and tags cannot be
changed or reused. Each release includes an SPDX 2.3 software bill of materials
and GitHub's immutable-release attestation. The destination machine requires
Linux, Node.js 24, OpenSSH, and 1Password CLI, but does not run npm.

Publication is authorized only by a workflow loaded from the protected default
branch. Staged tags are treated as untrusted input, and every downloadable asset
must match the independently signed release manifest before publication.
