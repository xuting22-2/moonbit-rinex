# Pinned local toolchain

Install compiler distribution `0.10.14+7d59c7ec9` as recorded in `.moonbit-version`. Moon CLI reports `0.1.20260920`; this CLI build date is not the installer's compiler-version parameter. Node 24 for file host, Python 3.14 standard library for independent reference only. Core library supports JS/Wasm-GC without Node/Python. The core performs native CRINEX1.0/3.0 differential restoration; it does not perform networking, filesystem IO or gzip container decompression.

GitHub CI uses Ubuntu 24.04, Node 24.11.0 and Python 3.14.0. Official actions are pinned by commit SHA; the official Unix installer is checksum-pinned, and reads the exact compiler distribution from `.moonbit-version`. Every run prints actual tool versions. Local SDK installations remain unchanged. See [CI reproduction and limits](docs/CI.md).
