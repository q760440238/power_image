package com.taobao.power_image_example.macrobenchmark

import android.os.SystemClock
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.MemoryUsageMetric
import androidx.benchmark.macro.StartupMode
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
    @OptIn(ExperimentalMetricApi::class)
    fun powerImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_power_image",
        pageLabel = "benchmark_power_image_page",
        includePowerImageTrace = true,
    )

    @Test
    fun cachedNetworkImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_cached_network_image",
        pageLabel = "benchmark_cached_network_image_page",
        includePowerImageTrace = false,
    )

    @Test
    fun extendedImageAnimatedScroll() = animatedScroll(
        entryLabel = "benchmark_extended_image",
        pageLabel = "benchmark_extended_image_page",
        includePowerImageTrace = false,
    )

    @OptIn(ExperimentalMetricApi::class)
    private fun animatedScroll(
        entryLabel: String,
        pageLabel: String,
        includePowerImageTrace: Boolean,
    ) = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = if (includePowerImageTrace) {
            listOf(
                FrameTimingMetric(),
                MemoryUsageMetric(MemoryUsageMetric.Mode.Max),
                TraceSectionMetric(
                    sectionName = "PowerImage#renderAnimatedFrames",
                    mode = TraceSectionMetric.Mode.Count,
                ),
                TraceSectionMetric(
                    sectionName = "PowerImage#renderAnimatedFrames",
                    mode = TraceSectionMetric.Mode.Average,
                ),
            )
        } else {
            listOf(
                FrameTimingMetric(),
                MemoryUsageMetric(MemoryUsageMetric.Mode.Max),
            )
        },
        compilationMode = CompilationMode.Full(),
        startupMode = StartupMode.WARM,
        iterations = 5,
        setupBlock = {
            pressHome()
        },
    ) {
        startActivityAndWait()

        val texturePage = device.wait(
            Until.findObject(By.desc(entryLabel)),
            UI_TIMEOUT_MILLIS,
        )
        requireNotNull(texturePage) { "$entryLabel entry was not found" }
        texturePage.click()
        check(
            device.wait(
                Until.hasObject(By.desc(pageLabel)),
                UI_TIMEOUT_MILLIS,
            ),
        ) {
            "$pageLabel did not open"
        }

        // Allow the first visible animated WebP textures to start.
        SystemClock.sleep(1_000)
        repeat(6) {
            device.swipe(
                device.displayWidth / 2,
                device.displayHeight * 4 / 5,
                device.displayWidth / 2,
                device.displayHeight / 5,
                20,
            )
            SystemClock.sleep(350)
        }
    }

    private companion object {
        const val TARGET_PACKAGE = "com.taobao.power_image_example"
        const val UI_TIMEOUT_MILLIS = 10_000L
    }
}
