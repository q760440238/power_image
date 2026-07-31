package com.taobao.power_image_example;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PowerImageGlideResultTest {
    @Test
    public void usesPlatformAnimatedWebpOnlyWhenImageDecoderIsAvailable() {
        assertFalse(PowerImageGlideModule.usePlatformAnimatedWebp(27));
        assertTrue(PowerImageGlideModule.usePlatformAnimatedWebp(28));
        assertTrue(PowerImageGlideModule.usePlatformAnimatedWebp(36));
    }
}
