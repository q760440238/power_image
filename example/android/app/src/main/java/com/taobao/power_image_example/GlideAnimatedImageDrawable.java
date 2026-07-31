package com.taobao.power_image_example;

import android.annotation.TargetApi;
import android.graphics.drawable.AnimatedImageDrawable;
import android.graphics.drawable.Drawable;

import com.taobao.power_image.loader.FlutterMultiFrameImage;

/** Android 9+ animated WebP backed by the platform ImageDecoder. */
@TargetApi(28)
public final class GlideAnimatedImageDrawable extends FlutterMultiFrameImage {
    public GlideAnimatedImageDrawable(
            AnimatedImageDrawable drawable, boolean needRecycle) {
        super(drawable, needRecycle);
    }

    @Override
    protected void onStart(Drawable who) {
        ((AnimatedImageDrawable) who).start();
    }

    @Override
    protected void onStop(Drawable who) {
        ((AnimatedImageDrawable) who).stop();
    }

    @Override
    protected void onRelease(Drawable who) {
        ((AnimatedImageDrawable) who).stop();
    }

    @Override
    public int getFrameCount() {
        // AnimatedImageDrawable does not expose its exact frame count. A value
        // greater than one preserves the multi-frame lifecycle semantics.
        return 2;
    }
}
