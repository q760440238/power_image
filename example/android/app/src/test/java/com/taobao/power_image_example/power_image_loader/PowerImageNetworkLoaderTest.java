package com.taobao.power_image_example.power_image_loader;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PowerImageNetworkLoaderTest {
    @Test
    public void recognizesWebpPathWithQueryAndMixedCase() {
        assertTrue(PowerImageNetworkLoader.isWebpUrl(
                "http://127.0.0.1/animal.WEBP?library=power_image&item=3"));
    }

    @Test
    public void rejectsNonWebpAndMissingSources() {
        assertFalse(PowerImageNetworkLoader.isWebpUrl("https://example.test/animal.gif"));
        assertFalse(PowerImageNetworkLoader.isWebpUrl("https://example.test/webp?id=3"));
        assertFalse(PowerImageNetworkLoader.isWebpUrl(null));
    }
}
