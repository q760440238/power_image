# Cache and Surface lifecycle benchmark — 22041216C

Measured on a physical Redmi/Xiaomi `22041216C` (`xaga`), Android 14 / API 34,
build `OS2.0.12.0.ULOCNXM`. The benchmark APK is non-debuggable and the suite
uses `CompilationMode.Full`. Each cache path has 10 measured iterations; the
100-Surface release/rebuild path has 5. Every operation trace contains exactly
one matching async section.

| Data set | Iterations | Operation ms min / median / max | GPU max KB median | RSS anon max KB median |
| --- | ---: | ---: | ---: | ---: |
| Cold load | 10 | 28.053 / 39.628 / 44.500 | 83,236 | 62,036 |
| Raw-byte disk hit | 10 | 25.068 / 31.566 / 61.100 | 99,088 | 63,598 |
| Flutter ImageCache hit | 10 | 7.904 / 12.652 / 28.000 | 93,540 | 64,380 |
| Release/rebuild 100 native Surfaces | 5 | 431.939 / 530.077 / 541.505 | 148,708 | 179,728 |

Relative to cold load, the median first-frame operation is 20.3% shorter for a
raw-byte disk hit and 68.1% shorter for a Flutter ImageCache hit. The Surface
case measures the complete removal, teardown fence, rebuild, and first real
frame from all 100 images; it completed all five iterations without a process
crash or timeout.

Perfetto traces were emitted under:

`/storage/emulated/0/Android/media/com.taobao.power_image_example.macrobenchmark`

`summary.json` records the four successful instrumentation summaries in a
machine-readable form. `surface-rebuild-100-benchmarkData.json` is the raw
AndroidX Benchmark output captured before the output directory was reused by a
later invocation.
