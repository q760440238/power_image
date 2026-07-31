package com.taobao.power_image.request;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class PowerImageRequestConfigTest {
    @Test
    public void acceptsIntegerAndDoubleDimensions() {
        assertEquals(30, PowerImageRequestConfig.dimensionInPixels(10, 3f));
        assertEquals(31, PowerImageRequestConfig.dimensionInPixels(10.5, 3f));
    }

    @Test
    public void rejectsInvalidDimensions() {
        assertEquals(0, PowerImageRequestConfig.dimensionInPixels(null, 3f));
        assertEquals(0, PowerImageRequestConfig.dimensionInPixels("10", 3f));
        assertEquals(0, PowerImageRequestConfig.dimensionInPixels(-1, 3f));
        assertEquals(0, PowerImageRequestConfig.dimensionInPixels(Double.NaN, 3f));
        assertEquals(0, PowerImageRequestConfig.dimensionInPixels(10, 0f));
    }

    @Test
    public void clampsOverflow() {
        assertEquals(
                Integer.MAX_VALUE,
                PowerImageRequestConfig.dimensionInPixels(Double.MAX_VALUE, 3f));
    }

    @Test
    public void srcStringIgnoresNonStringValues() {
        PowerImageRequestConfig config = new PowerImageRequestConfig();
        config.src = new java.util.HashMap<>();
        config.src.put("src", 42);

        assertNull(config.srcString());
    }
}
