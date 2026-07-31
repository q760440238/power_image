package com.taobao.power_image_example.macrobenchmark

import android.os.Build
import android.os.SystemClock
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.MemoryUsageMetric
import androidx.benchmark.macro.Metric
import androidx.benchmark.macro.TraceSectionMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@LargeTest
@RunWith(AndroidJUnit4::class)
class AnimatedTextureBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun powerImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_power_image",
        pageLabel = "benchmark_power_image_page",
    )

    @Test
    fun cachedNetworkImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_cached_network_image",
        pageLabel = "benchmark_cached_network_image_page",
    )

    @Test
    fun extendedImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_extended_image",
        pageLabel = "benchmark_extended_image_page",
    )

    @OptIn(ExperimentalMetricApi::class)
    private fun animatedScroll(
        entryLabel: String,
        pageLabel: String,
    ) = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        // Flutter/Impeller does not draw through Android HWUI's RenderThread,
        // so FrameTimingMetric cannot observe this SurfaceView. These Flutter
        // and raster sections are comparable across all three libraries.
        metrics = animatedMetrics(),
        compilationMode = CompilationMode.Full(),
        // This is a steady-state scroll benchmark, not an app-start benchmark.
        startupMode = null,
        iterations = 5,
        setupBlock = {
            killProcess()
            pressHome()
            startActivityAndWait()

            val texturePage = device.wait(
                Until.findObject(By.desc(entryLabel)),
                UI_TIMEOUT_MILLIS,
            )
            requireNotNull(texturePage) { "$entryLabel entry was not found" }
            texturePage.click()
            if (!device.wait(Until.hasObject(By.desc(pageLabel)), UI_TIMEOUT_MILLIS)) {
                // Re-resolve the semantics node once instead of retrying a
                // stale UiObject after fixture/Impeller initialization.
                val retryEntry = device.wait(
                    Until.findObject(By.desc(entryLabel)),
                    UI_TIMEOUT_MILLIS,
                )
                requireNotNull(retryEntry) { "$entryLabel retry entry was not found" }
                retryEntry.click()
                check(
                    device.wait(
                        Until.hasObject(By.desc(pageLabel)),
                        UI_TIMEOUT_MILLIS,
                    ),
                ) {
                    "$pageLabel did not open after retry"
                }
            }

            // Exclude fixture startup, navigation and initial decoding from
            // the steady-state trace shared by all three libraries.
            SystemClock.sleep(3_000)
        },
    ) {
        repeat(6) { gesture ->
            val scrollTowardEnd = gesture % 2 == 0
            val startY = if (scrollTowardEnd) {
                device.displayHeight * 4 / 5
            } else {
                device.displayHeight / 5
            }
            val endY = if (scrollTowardEnd) {
                device.displayHeight / 5
            } else {
                device.displayHeight * 4 / 5
            }
            check(
                device.swipe(
                    device.displayWidth / 2,
                    startY,
                    device.displayWidth / 2,
                    endY,
                    20,
                ),
            ) {
                "Swipe gesture could not be injected"
            }
            SystemClock.sleep(350)
        }
    }

    @OptIn(ExperimentalMetricApi::class)
    private fun animatedMetrics(): List<Metric> = buildList {
        // Android 10 Flutter traces do not expose CALLBACK_ANIMATION. Asking
        // AndroidX Benchmark 1.4.1 to aggregate an empty section crashes its
        // median calculation, so those devices report raster and memory only.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(
                TraceSectionMetric(
                    sectionName = "CALLBACK_ANIMATION",
                    mode = TraceSectionMetric.Mode.Count,
                    label = "flutterUiFrame",
                    targetPackageOnly = true,
                ),
            )
            add(
                TraceSectionMetric(
                    sectionName = "CALLBACK_ANIMATION",
                    mode = TraceSectionMetric.Mode.Average,
                    label = "flutterUiFrame",
                    targetPackageOnly = true,
                ),
            )
            add(
                TraceSectionMetric(
                    sectionName = "CALLBACK_ANIMATION",
                    mode = TraceSectionMetric.Mode.Max,
                    label = "flutterUiFrame",
                    targetPackageOnly = true,
                ),
            )
        }
        add(
            TraceSectionMetric(
                sectionName = "queueBuffer",
                mode = TraceSectionMetric.Mode.Count,
                label = "flutterRasterQueueBuffer",
                targetPackageOnly = true,
            ),
        )
        add(
            TraceSectionMetric(
                sectionName = "queueBuffer",
                mode = TraceSectionMetric.Mode.Average,
                label = "flutterRasterQueueBuffer",
                targetPackageOnly = true,
            ),
        )
        add(
            TraceSectionMetric(
                sectionName = "queueBuffer",
                mode = TraceSectionMetric.Mode.Max,
                label = "flutterRasterQueueBuffer",
                targetPackageOnly = true,
            ),
        )
        add(MemoryUsageMetric(MemoryUsageMetric.Mode.Max))
    }

    private companion object {
        const val TARGET_PACKAGE = "com.taobao.power_image_example"
        const val UI_TIMEOUT_MILLIS = 10_000L
    }
}
