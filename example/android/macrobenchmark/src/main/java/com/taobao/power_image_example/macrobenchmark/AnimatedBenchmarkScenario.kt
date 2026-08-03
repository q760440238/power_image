package com.taobao.power_image_example.macrobenchmark

import android.os.Build
import android.os.SystemClock
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.MemoryUsageMetric
import androidx.benchmark.macro.Metric
import androidx.benchmark.macro.TraceSectionMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until

internal const val TARGET_PACKAGE = "com.taobao.power_image_example"
internal const val UI_TIMEOUT_MILLIS = 10_000L

@OptIn(ExperimentalMetricApi::class)
internal fun MacrobenchmarkRule.measureAnimatedScroll(
    entryLabel: String,
    pageLabel: String,
    includeNativeFrameTrace: Boolean = false,
) = measureRepeated(
    packageName = TARGET_PACKAGE,
    metrics = animatedMetrics(includeNativeFrameTrace),
    compilationMode = CompilationMode.Full(),
    startupMode = null,
    iterations = 5,
    setupBlock = {
        killProcess()
        pressHome()
        startActivityAndWait()

        val entry = device.wait(Until.findObject(By.desc(entryLabel)), UI_TIMEOUT_MILLIS)
        requireNotNull(entry) { "$entryLabel entry was not found" }
        entry.click()
        if (!device.wait(Until.hasObject(By.desc(pageLabel)), UI_TIMEOUT_MILLIS)) {
            val retryEntry = device.wait(
                Until.findObject(By.desc(entryLabel)),
                UI_TIMEOUT_MILLIS,
            )
            requireNotNull(retryEntry) { "$entryLabel retry entry was not found" }
            retryEntry.click()
            check(device.wait(Until.hasObject(By.desc(pageLabel)), UI_TIMEOUT_MILLIS)) {
                "$pageLabel did not open after retry"
            }
        }

        // Keep fixture startup, navigation and initial decoding out of the
        // steady-state measurement for both execution paths.
        SystemClock.sleep(3_000)
    },
) {
    repeat(24) { gesture ->
        val scrollTowardEnd = gesture < 12
        val startY = if (scrollTowardEnd) device.displayHeight * 4 / 5
        else device.displayHeight / 5
        val endY = if (scrollTowardEnd) device.displayHeight / 5
        else device.displayHeight * 4 / 5
        var injected = device.swipe(
            device.displayWidth / 2,
            startY,
            device.displayWidth / 2,
            endY,
            20,
        )
        if (!injected) {
            // Some vendor input stacks transiently reject the first injection
            // immediately after trace start. Retry once; a second failure is a
            // real invalid iteration and must still fail the benchmark.
            SystemClock.sleep(150)
            injected = device.swipe(
                device.displayWidth / 2,
                startY,
                device.displayWidth / 2,
                endY,
                20,
            )
        }
        check(injected) { "Swipe gesture could not be injected after retry" }
        SystemClock.sleep(350)
    }
}

@OptIn(ExperimentalMetricApi::class)
private fun animatedMetrics(includeNativeFrameTrace: Boolean): List<Metric> = buildList {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        addTraceModes("CALLBACK_ANIMATION", "flutterUiFrame")
    }
    addTraceModes("queueBuffer", "flutterRasterQueueBuffer")
    if (includeNativeFrameTrace) {
        addTraceModes("PowerImage#renderAnimatedFrames", "nativeDrawableSurfaceFrame")
    }
    add(MemoryUsageMetric(MemoryUsageMetric.Mode.Max))
}

@OptIn(ExperimentalMetricApi::class)
private fun MutableList<Metric>.addTraceModes(sectionName: String, label: String) {
    add(
        TraceSectionMetric(
            sectionName = sectionName,
            mode = TraceSectionMetric.Mode.Count,
            label = label,
            targetPackageOnly = true,
        ),
    )
    add(
        TraceSectionMetric(
            sectionName = sectionName,
            mode = TraceSectionMetric.Mode.Average,
            label = label,
            targetPackageOnly = true,
        ),
    )
    add(
        TraceSectionMetric(
            sectionName = sectionName,
            mode = TraceSectionMetric.Mode.Max,
            label = label,
            targetPackageOnly = true,
        ),
    )
}
