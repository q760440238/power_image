package com.taobao.power_image_example.macrobenchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.MemoryUsageMetric
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
class FirstFrameDisplayBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun powerImageFirstFrameDisplayed() = firstFrame("power_image")

    @Test
    fun powerImageWidgetFirstFrameDisplayed() = firstFrame("power_image_widget")

    @Test
    fun cachedNetworkImageFirstFrameDisplayed() = firstFrame("cached_network_image")

    @Test
    fun extendedImageFirstFrameDisplayed() = firstFrame("extended_image")

    @OptIn(ExperimentalMetricApi::class)
    private fun firstFrame(library: String) = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(
            TraceSectionMetric(
                sectionName = "PowerImageBenchmark#firstFrameDisplayed",
                mode = TraceSectionMetric.Mode.Count,
                label = "firstFrameDisplayed",
                targetPackageOnly = true,
            ),
            TraceSectionMetric(
                sectionName = "PowerImageBenchmark#firstFrameDisplayed",
                mode = TraceSectionMetric.Mode.Average,
                label = "firstFrameDisplayed",
                targetPackageOnly = true,
            ),
            MemoryUsageMetric(MemoryUsageMetric.Mode.Max),
        ),
        compilationMode = CompilationMode.Full(),
        startupMode = null,
        iterations = 10,
        setupBlock = {
            killProcess()
            pressHome()
            startActivityAndWait()

            val benchmarkEntry = device.wait(
                Until.findObject(By.desc("benchmark_first_frame")),
                UI_TIMEOUT_MILLIS,
            )
            requireNotNull(benchmarkEntry) { "First-frame benchmark entry was not found" }
            benchmarkEntry.click()
            check(
                device.wait(
                    Until.hasObject(By.desc("benchmark_first_frame_menu")),
                    UI_TIMEOUT_MILLIS,
                ),
            ) { "First-frame benchmark menu did not open" }
        },
    ) {
        val libraryEntry = device.wait(
            Until.findObject(By.desc("first_frame_$library")),
            UI_TIMEOUT_MILLIS,
        )
        requireNotNull(libraryEntry) { "$library first-frame entry was not found" }
        libraryEntry.click()
        check(
            device.wait(
                Until.hasObject(By.descContains("first_frame_${library}_displayed")),
                UI_TIMEOUT_MILLIS,
            ),
        ) { "$library did not display its first frame" }
    }
}
