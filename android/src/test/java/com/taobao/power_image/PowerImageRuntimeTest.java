package com.taobao.power_image;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PowerImageRuntimeTest {
    @Test
    public void detectsAndroidStudioEmulator() {
        assertTrue(PowerImageRuntime.isProbablyEmulator(
                "google/sdk_gphone64_x86_64/emu64xa:16/test-keys",
                "sdk_gphone64_x86_64", "Google", "google", "emu64xa",
                "sdk_gphone64_x86_64", "ranchu"));
    }

    @Test
    public void doesNotClassifyPhysicalHuaweiAsEmulator() {
        assertFalse(PowerImageRuntime.isProbablyEmulator(
                "HUAWEI/VOG-AL10/HWVOG:10/HUAWEIVOG-AL10/user/release-keys",
                "VOG-AL10", "HUAWEI", "HUAWEI", "HWVOG", "VOG-AL10", "kirin980"));
    }

    @Test
    public void handlesMissingBuildFields() {
        assertFalse(PowerImageRuntime.isProbablyEmulator(
                null, null, null, null, null, null, null));
    }
}
