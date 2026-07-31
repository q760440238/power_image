package com.taobao.power_image;

import android.os.Build;

import java.util.Locale;

/** Runtime capability checks used to choose the safest Android rendering path. */
public final class PowerImageRuntime {
    private static final boolean EMULATOR = isProbablyEmulator(
            Build.FINGERPRINT,
            Build.MODEL,
            Build.MANUFACTURER,
            Build.BRAND,
            Build.DEVICE,
            Build.PRODUCT,
            Build.HARDWARE);

    private PowerImageRuntime() {
    }

    public static boolean isEmulator() {
        return EMULATOR;
    }

    static boolean isProbablyEmulator(
            String fingerprint,
            String model,
            String manufacturer,
            String brand,
            String device,
            String product,
            String hardware) {
        String normalizedFingerprint = normalize(fingerprint);
        String normalizedModel = normalize(model);
        String normalizedManufacturer = normalize(manufacturer);
        String normalizedBrand = normalize(brand);
        String normalizedDevice = normalize(device);
        String normalizedProduct = normalize(product);
        String normalizedHardware = normalize(hardware);

        return normalizedFingerprint.startsWith("generic")
                || normalizedFingerprint.startsWith("unknown")
                || normalizedFingerprint.contains("emulator")
                || normalizedModel.contains("google_sdk")
                || normalizedModel.contains("emulator")
                || normalizedModel.contains("android sdk built for")
                || normalizedManufacturer.contains("genymotion")
                || (normalizedBrand.startsWith("generic")
                        && normalizedDevice.startsWith("generic"))
                || normalizedProduct.contains("sdk_gphone")
                || normalizedProduct.equals("google_sdk")
                || normalizedProduct.equals("sdk")
                || normalizedProduct.contains("vbox86p")
                || normalizedHardware.contains("goldfish")
                || normalizedHardware.contains("ranchu")
                || normalizedHardware.contains("vbox86");
    }

    private static String normalize(String value) {
        return value == null ? "" : value.toLowerCase(Locale.US);
    }
}
