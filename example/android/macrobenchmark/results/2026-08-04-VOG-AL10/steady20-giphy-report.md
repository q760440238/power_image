# 20 个不同 GIPHY 动画 WebP 稳态播放对比

测试日期：2026-08-04

## 环境与口径

- 设备：Huawei VOG-AL10，Android 10 / API 29，8 核 CPU。
- 素材：从 `https://giphy.com/explore/webp` 当前结果中选取 20 个不同动画，原 GIF 使用 FFmpeg 8.1.2 `libwebp_anim` 转为 WebP；保持原尺寸、总时长和循环，不缩放、不抽帧。完整来源、尺寸、帧数、时长和 SHA-256 位于同目录的 `giphy-materials-manifest.csv`。
- 布局：4×5 固定网格，20 张全部可见，每格约 270×270 物理像素。
- PowerImage：普通 WebP 使用 Flutter codec 路径。
- ExtendedImage：10.1.0，Flutter codec。
- 原生基线：不启动 Flutter Engine 的 Android Activity，Glide 4.16.0 + `webpdecoder` 2.7.4.16.0，20 个 ImageView。
- 每个方案 5 轮交错执行；每轮预热 12 秒，连续采样 20 秒，轮间冷却 8 秒。CPU/RSS/GPU 频率共 100 个一秒窗口；PSS/Graphics 每方案 5 份快照。
- CPU `100%` 表示占满一个核心；括号内为除以 8 核后的整机 CPU 容量占比。
- 电池温度始终为 35–36°C。

## 正式结果

| 方案 | CPU P50 | CPU P95 | RSS P50 / P95 KiB | PSS P50 / P95 KiB | Graphics P50 / P95 KiB | GPU 频率 P50 / P95 MHz | Surface FPS P50 | 帧间隔 P95 的轮次中位数 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| PowerImage Flutter codec | 133.704% (16.713%) | 136.405% (17.051%) | 291,516 / 298,901.8 | 150,736 / 157,014.4 | 47,436 / 48,741.6 | 139 / 139 | 60.116 | 18.037 |
| ExtendedImage 10.1.0 | 133.857% (16.732%) | 136.022% (17.003%) | 287,424 / 309,283 | 148,206 / 160,580.4 | 48,548 / 53,585.6 | 139 / 139 | 60.132 | 18.205 |
| 原生 Glide 4.16.0 | 138.088% (17.261%) | 154.886% (19.361%) | 249,016 / 253,772 | 112,489 / 114,503.4 | 43,728 / 45,159.2 | 139 / 139 | 60.176 | 20.909 |

## PowerImage 相对差值

负值代表 PowerImage 更低。

| 对比对象 | CPU P50 | CPU P95 | RSS P50 | RSS P95 | PSS P50 | PSS P95 | Graphics P50 | Graphics P95 | 帧间隔 P95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ExtendedImage | -0.11% | +0.28% | +1.42% | -3.36% | +1.71% | -2.22% | -2.29% | -9.04% | -0.92% |
| 原生 Glide | -3.17% | -11.93% | +17.07% | — | +34.00% | — | +8.48% | — | -13.74% |

## 结论

1. PowerImage 与 ExtendedImage 的稳态 CPU 和呈现帧率实质持平，CPU P50 只差 0.11%，不能宣称有显著 CPU 领先。
2. PowerImage 的中位 PSS 比 ExtendedImage 高 2,530 KiB（1.71%），但尾部更稳：P95 PSS 低 2.22%、P95 RSS 低 3.36%、P95 Graphics 低 9.04%。优势主要在内存尾部波动，不在中位 CPU。
3. 相比纯原生 Glide，PowerImage 的 CPU P50 低 3.17%、P95 低 11.93%，帧间隔尾部也更好；但 Flutter Engine/Impeller 的固定成本使 PSS 高 38,247 KiB（相对 Glide +34.00%）。原生 Glide 仍有明显的进程内存优势。
4. 三方均约 60 FPS；GPU 频率在全部 300 个样本中均为 139 MHz，即该机 720 MHz 上限的 19.31%。这表明场景主要由 CPU 解码/调度驱动，GPU 没有升频。
5. 量产内核拒绝读取 `gpu_scene_aware/utilisation`，`simpleperf` 也无权打开目标进程 perf event。因此 139 MHz 只能作为负载代理，不能解读为 19.31% GPU utilization。

原始机器可读结果：`steady20-giphy-5x.json`。
