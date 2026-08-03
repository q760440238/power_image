# VOG-AL10 physical-device results (2026-08-03)

Device: Huawei VOG-AL10, Android 10 / API 29. Flutter 3.38.7, full AOT
compilation, in-process loopback HTTP fixture. Competitors are
ExtendedImage 10.1.0 and CachedNetworkImage 3.4.1. P95 uses nearest-rank over
the raw iteration values. RSS and heap figures are peak-KB medians.

## Final four scenarios

| Scenario | Iterations | P50 ms | P95 ms | RSS P50 KB | Dart heap P50 KB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold first frame: PowerImage | 10 | 41.967 | 46.382 | 251,406 | 1,810.5 |
| Cold first frame: ExtendedImage 10.1.0 | 10 | 42.390 | 63.427 | 258,870 | 1,786 |
| Cold first frame: CachedNetworkImage 3.4.1 | 10 | 75.667 | 78.328 | 259,114 | 1,883 |
| Encoded-byte disk hit | 20 | 27.936 | 48.598 | 227,670 | 1,687 |
| Flutter ImageCache hit | 10 | 15.878 | 22.868 | 228,834 | 1,671 |
| Release/rebuild 100 native Surfaces | 5 | 962.568 | 2,337.305 | 593,172 | 30,432 |

All iterations completed their required real-frame marker. The disk-hit set
contains three 45-49 ms scheduling outliers; its isolated `fromFilePath` A/B
below is therefore the appropriate evidence for that change rather than
claiming the final mixed-build P95 as an improvement.

PowerImage is 1.0% faster than ExtendedImage at cold P50 and 26.9% faster at
cold P95. Against CachedNetworkImage it is 44.5% faster at P50 and 40.8%
faster at P95 in this fixture.

## Kept-change A/B gates

| Change | Before P50/P95 ms | After P50/P95 ms | Result |
| --- | ---: | ---: | --- |
| Disk `ImmutableBuffer.fromFilePath` | 32.834 / 38.803 | 27.509 / 36.203 | -16.2% / -6.7% |
| Deferred/bounded cache maintenance | 241.172 / 249.526 | 229.213 / 232.482 | -5.0% / -6.8% |
| Schedule the real first `getNextFrame()` | 45.145 / 77.059 | 41.967 / 46.382 | -7.0% / -39.8% |
| Standard Flutter `Image` widget fast path | 44.361 / 60.090 | 42.646 / 59.193 | -3.9% / -1.5% |
| Animated raster `queueBuffer` average | 0.560 / 0.582 | 0.543 / 0.559 | -3.0% / -3.8% |

The final animated run submitted a median 826 frames versus 819 before the
standard-widget fast path, so the lower timings were not obtained by dropping
frames. Private RSS also stayed flat (126,916 KB before, 126,804 KB after).

## Raw files used above

- `01-formal-baseline-first-frame-10x.json`
- `02-before-file-buffer-raw-disk-10x.json`
- `03-after-file-buffer-raw-disk-10x.json`
- `04-before-cache-maintenance-write100-5x.json`
- `08-after-cache-maintenance-16lane-write100-5x.json`
- `09-after-cache-maintenance-16lane-repeat-write100-5x.json`
- `14-after-first-frame-only-6lane-cold-10x.json`
- `15-after-first-frame-only-6lane-animated-scroll-5x.json`
- `16-before-standard-image-widget-cold-10x.json`
- `17-after-standard-image-widget-cold-10x.json`
- `20-after-standard-image-low-quality-animated-scroll-5x.json`
- `21-final-raw-bytes-disk-hit-10x.json`
- `22-final-flutter-image-cache-hit-10x.json`
- `23-final-release-rebuild-100-surfaces-5x.json`
- `24-final-raw-bytes-disk-hit-repeat-10x.json`

Rejected tuning runs are intentionally excluded from the PR result set.
