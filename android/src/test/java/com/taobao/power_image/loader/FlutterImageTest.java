package com.taobao.power_image.loader;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class FlutterImageTest {
    @Test
    public void fencesHwuiOnEverySupportedAndroidVersion() {
        assertFalse(FlutterImage.needsFencedHwuiRenderer(28));
        assertTrue(FlutterImage.needsFencedHwuiRenderer(29));
        assertTrue(FlutterImage.needsFencedHwuiRenderer(34));
    }

    @Test
    public void waitsForPresentOnlyForTheTeardownFence() {
        assertFalse(FencedSurfaceRenderer.waitForPresent(false));
        assertTrue(FencedSurfaceRenderer.waitForPresent(true));
    }
}
