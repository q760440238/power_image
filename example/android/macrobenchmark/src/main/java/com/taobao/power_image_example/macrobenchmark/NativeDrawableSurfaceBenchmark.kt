package com.taobao.power_image_example.macrobenchmark

import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Measures PowerImage's explicit native Drawable -> Surface execution path. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class NativeDrawableSurfaceBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun powerImageNativeDrawableSurfaceAnimatedScroll() =
        benchmarkRule.measureAnimatedScroll(
            entryLabel = "benchmark_power_image_native_surface",
            pageLabel = "benchmark_power_image_native_surface_page",
            includeNativeFrameTrace = true,
        )
}
