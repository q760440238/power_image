package com.taobao.power_image.loader;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class FlutterEncodedImageTest {
    @Test
    public void exposesAndReleasesEncodedBytes() {
        byte[] bytes = new byte[]{1, 2, 3};
        FlutterEncodedImage image = new FlutterEncodedImage(bytes, 20, 10, 2);

        assertArrayEquals(bytes, image.getEncodedData());
        assertEquals(20, image.getWidth());
        assertEquals(10, image.getHeight());
        assertEquals(2, image.getFrameCount());
        assertTrue(image.isValid());

        image.release();
        assertNull(image.getEncodedData());
        assertFalse(image.isValid());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsInvalidDimensions() {
        new FlutterEncodedImage("/cache/image.webp", 0, 10, 2);
    }
}
