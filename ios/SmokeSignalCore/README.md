# SmokeSignalCore

Pure Swift core logic for SmokeSignal on iOS:

- Frame encoding/decoding + CRC32
- Fountain (LT) encoder/decoder for lossy symbol streams

This module is intentionally UI-free so it can be unit tested with `swift test`
and embedded in an iOS app target.

## Run Tests

From the repo root:

```bash
cd Downloads/smokesignal-master/ios/SmokeSignalCore
swift test
```

