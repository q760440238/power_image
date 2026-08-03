package com.taobao.power_image_example.macrobenchmark

import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Apples-to-apples Flutter codec comparison across the three libraries. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class FlutterCodecAnimatedWebpBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun powerImageFlutterCodecAnimatedScroll() = benchmarkRule.measureAnimatedScroll(
        entryLabel = "benchmark_power_image",
        pageLabel = "benchmark_power_image_page",
    )

    @Test
    fun cachedNetworkImageAnimatedScroll() = benchmarkRule.measureAnimatedScroll(
        entryLabel = "benchmark_cached_network_image",
        pageLabel = "benchmark_cached_network_image_page",
    )

    @Test
    fun extendedImageAnimatedScroll() = benchmarkRule.measureAnimatedScroll(
        entryLabel = "benchmark_extended_image",
        pageLabel = "benchmark_extended_image_page",
    )
}
