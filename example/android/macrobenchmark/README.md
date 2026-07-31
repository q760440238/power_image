# Android animated texture Macrobenchmark

This benchmark opens a deterministic grid backed by an in-memory animated
WebP fixture and records both Android frame timing and the count/average
duration of `PowerImage#renderAnimatedFrames` batches while scrolling. It
performs no network requests.

Run it from `example/android`:

```shell
./gradlew :macrobenchmark:connectedCheck
```

Use a physical Android 14+ device for performance numbers. Emulator execution
is enabled only as a functional check and must not be treated as a performance
baseline.
