package com.taobao.power_image_example;

import android.content.Context;
import android.os.Build;

import androidx.annotation.NonNull;

import com.bumptech.glide.Glide;
import com.bumptech.glide.GlideBuilder;
import com.bumptech.glide.Registry;
import com.bumptech.glide.integration.webp.WebpGlideLibraryModule;
import com.bumptech.glide.module.GlideModule;

/** Selects the lowest-overhead animated WebP decoder available on Android. */
public final class PowerImageGlideModule implements GlideModule {
    @Override
    public void applyOptions(
            @NonNull Context context, @NonNull GlideBuilder builder) {
    }

    @Override
    public void registerComponents(
            @NonNull Context context,
            @NonNull Glide glide,
            @NonNull Registry registry) {
        if (!usePlatformAnimatedWebp(Build.VERSION.SDK_INT)) {
            new WebpGlideLibraryModule().registerComponents(context, glide, registry);
        }
    }

    static boolean usePlatformAnimatedWebp(int sdkInt) {
        return sdkInt >= Build.VERSION_CODES.P;
    }
}
