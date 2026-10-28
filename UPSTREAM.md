# Upstream provenance

DashLink incorporates [PlayPort](https://github.com/youcci/playport), which is
based on DiPlay and xcertplay. The receiver baseline is vendored in `Receiver/`.

- Source: https://github.com/youcci/playport
- Revision: `9a0882dd0ffe48e467b59d58b12d81391df55ade`
- Baseline title: “Refresh README screenshots with live CarPlay”
- License: GPL-3.0; see `LICENSE` and `Receiver/LICENSE`.

The first commit imports that exact tracked snapshot. Later commits contain
DashLink's build updates, native Bluetooth transport, audio fixes, Mac interface,
and release tooling. Original file contents, notices, and executable modes are
preserved in the baseline. This is a snapshot import, not upstream Git history.

No accessory identity or user's pairing state is included. The optional local
setup and its provenance are described in `NOTICE.txt` and `README.md`.
