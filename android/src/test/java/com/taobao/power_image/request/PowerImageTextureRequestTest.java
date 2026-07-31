package com.taobao.power_image.request;

import static org.junit.Assert.assertArrayEquals;

import org.junit.Test;

public class PowerImageTextureRequestTest {
    @Test
    public void fitsInsideRequestedPhysicalPixels() {
        assertArrayEquals(
                new int[]{420, 420},
                PowerImageTextureRequest.fitTextureSize(512, 512, 420, 420));
        assertArrayEquals(
                new int[]{400, 200},
                PowerImageTextureRequest.fitTextureSize(800, 400, 400, 0));
    }

    @Test
    public void preservesAspectRatioAndDoesNotUpscale() {
        assertArrayEquals(
                new int[]{300, 150},
                PowerImageTextureRequest.fitTextureSize(300, 150, 900, 900));
        assertArrayEquals(
                new int[]{300, 150},
                PowerImageTextureRequest.fitTextureSize(800, 400, 300, 300));
    }

    @Test
    public void enforcesTextureLimitAndRejectsInvalidSources() {
        assertArrayEquals(
                new int[]{1920, 960},
                PowerImageTextureRequest.fitTextureSize(4000, 2000, 0, 0));
        assertArrayEquals(
                new int[]{0, 0},
                PowerImageTextureRequest.fitTextureSize(0, 100, 50, 50));
    }

    @Test
    public void estimatesThreeRgbaSurfaceBuffersWithoutIntegerOverflow() {
        assertArrayEquals(
                new long[]{2_764_800L, 0L, 49_152_000_000L},
                new long[]{
                        PowerImageTextureRequest.estimateSurfaceBufferBytes(480, 480),
                        PowerImageTextureRequest.estimateSurfaceBufferBytes(0, 480),
                        PowerImageTextureRequest.estimateSurfaceBufferBytes(64_000, 64_000)});
    }
}
