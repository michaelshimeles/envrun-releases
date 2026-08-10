# envrun releases

Public, checksum-verified Linux release artifacts for envrun.

Install the latest release:

```sh
curl -fsSL https://michaelshimeles.github.io/envrun-releases/install | sh
```

Each `releases/vX.Y.Z/` directory is immutable. The private source repository publishes a compiled archive, its SHA-256 checksum, and the installer from a tagged, tested build. The destination machine requires Node.js 24 but does not run npm.
