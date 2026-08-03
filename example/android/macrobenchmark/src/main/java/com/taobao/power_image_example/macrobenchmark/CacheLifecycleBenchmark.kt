package com.taobao.power_image_example.macrobenchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.MemoryUsageMetric
import androidx.benchmark.macro.MacrobenchmarkScope
import androidx.benchmark.macro.TraceSectionMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.filters.SdkSuppress
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@LargeTest
@SdkSuppress(minSdkVersion = 29)
@RunWith(AndroidJUnit4::class)
class CacheLifecycleBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun coldLoad() = measureCachePath(
        mode = "cold",
        traceName = "PowerImageBenchmark#cold",
    )

    @Test
    fun rawBytesDiskHit() = measureCachePath(
        mode = "raw_bytes_disk",
        traceName = "PowerImageBenchmark#raw_bytes_disk",
    )

    @Test
    fun flutterImageCacheHit() = measureCachePath(
        mode = "flutter_image_cache",
        traceName = "PowerImageBenchmark#flutter_image_cache",
    )

    @Test
    fun write100RawByteEntries() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = lifecycleMetrics("PowerImageBenchmark#cacheWrite100"),
        compilationMode = CompilationMode.Full(),
        startupMode = null,
        iterations = 5,
        setupBlock = {
            openBenchmarkRoute("/benchmark/cache_write_100")
            check(
                device.wait(
                    Until.hasObject(By.descContains("cache_write_100_ready")),
                    30_000L,
                ),
            ) { "100-image cache write benchmark did not become ready" }
        },
    ) {
        sendBenchmarkCommand("cache_write_100:run")
        check(
            device.wait(
                Until.hasObject(By.descContains("cache_write_100_complete")),
                60_000L,
            ),
        ) { "100 images did not finish display and cache maintenance" }
    }

    @Test
    fun releaseAndRebuild100NativeSurfaces() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = lifecycleMetrics("PowerImageBenchmark#surfaceRebuild100"),
        compilationMode = CompilationMode.Full(),
        startupMode = null,
        iterations = 5,
        setupBlock = {
            openBenchmarkRoute("/benchmark/surface_rebuild")
            check(
                device.wait(
                    Until.hasObject(By.descContains("surface_rebuild_ready_0")),
                    30_000L,
                ),
            ) { "Initial 100 native surfaces did not become ready" }
        },
    ) {
        sendBenchmarkCommand("surface_rebuild:run")
        check(
            device.wait(
                Until.hasObject(By.descContains("surface_rebuild_complete_1")),
                30_000L,
            ),
        ) { "100 native surfaces did not finish release/rebuild" }
    }

    private fun measureCachePath(mode: String, traceName: String) =
        benchmarkRule.measureRepeated(
            packageName = TARGET_PACKAGE,
            metrics = lifecycleMetrics(traceName),
            compilationMode = CompilationMode.Full(),
            startupMode = null,
            iterations = 10,
            setupBlock = {
                openBenchmarkRoute("/benchmark/cache/$mode")
                check(
                    device.wait(
                            Until.hasObject(By.descContains("cache_benchmark_${mode}_ready")),
                        30_000L,
                    ),
                ) { "$mode benchmark did not finish preparation" }
            },
        ) {
            sendBenchmarkCommand("cache:$mode:run")
            check(
                device.wait(
                    Until.hasObject(By.descContains("cache_benchmark_${mode}_displayed")),
                    UI_TIMEOUT_MILLIS,
                ),
            ) { "$mode image did not display" }
        }

    private fun MacrobenchmarkScope.openBenchmarkRoute(route: String) {
        killProcess()
        device.executeShellCommand(
            "am start -W -n $TARGET_PACKAGE/.MainActivity " +
                "--es $BENCHMARK_ROUTE_EXTRA $route",
        )
    }

    private fun MacrobenchmarkScope.sendBenchmarkCommand(command: String) {
        device.executeShellCommand(
            "am start -W -n $TARGET_PACKAGE/.MainActivity " +
                "-f 0x20000000 --es $BENCHMARK_COMMAND_EXTRA $command",
        )
    }

    @OptIn(ExperimentalMetricApi::class)
    private fun lifecycleMetrics(traceName: String) = listOf(
        TraceSectionMetric(
            sectionName = traceName,
            mode = TraceSectionMetric.Mode.Count,
            label = "operationCount",
            targetPackageOnly = true,
        ),
        TraceSectionMetric(
            sectionName = traceName,
            mode = TraceSectionMetric.Mode.Average,
            label = "operationMs",
            targetPackageOnly = true,
        ),
        TraceSectionMetric(
            sectionName = traceName,
            mode = TraceSectionMetric.Mode.Max,
            label = "operationMaxMs",
            targetPackageOnly = true,
        ),
        MemoryUsageMetric(MemoryUsageMetric.Mode.Max),
    )

    companion object {
        private const val BENCHMARK_ROUTE_EXTRA = "power_image_benchmark_route"
        private const val BENCHMARK_COMMAND_EXTRA = "power_image_benchmark_command"
    }
}
