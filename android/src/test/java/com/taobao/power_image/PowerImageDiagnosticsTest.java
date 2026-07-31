package com.taobao.power_image;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import org.junit.Test;

public class PowerImageDiagnosticsTest {
    @Test
    public void valueTokenDoesNotExposeSourceText() {
        String source = "https://example.com/private/image.webp";

        assertEquals(Integer.toHexString(source.hashCode()),
                PowerImageDiagnostics.valueToken(source));
        assertNotEquals(source, PowerImageDiagnostics.valueToken(source));
        assertEquals("none", PowerImageDiagnostics.valueToken(null));
    }
}
