package com.taobao.power_image_example.power_image_loader;

import android.graphics.drawable.AnimatedImageDrawable;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.SystemClock;

import androidx.annotation.Nullable;

import com.bumptech.glide.integration.webp.decoder.WebpDrawable;
import com.bumptech.glide.load.DataSource;
import com.bumptech.glide.load.engine.GlideException;
import com.bumptech.glide.load.resource.bitmap.DownsampleStrategy;
import com.bumptech.glide.load.resource.gif.GifDrawable;
import com.bumptech.glide.RequestBuilder;
import com.bumptech.glide.RequestManager;
import com.bumptech.glide.request.RequestListener;
import com.bumptech.glide.request.FutureTarget;
import com.bumptech.glide.request.target.Target;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.PowerImageDiagnostics;
import com.taobao.power_image.loader.FlutterSingleFrameImage;
import com.taobao.power_image.loader.PowerImageResult;
import com.taobao.power_image.request.PowerImageRequestConfig;
import com.taobao.power_image_example.GlideAnimatedImageDrawable;
import com.taobao.power_image_example.GlideMultiFrameImage;
import com.taobao.power_image_example.GlideWebpMultiFrameImage;

final class PowerImageGlideResult {

    private PowerImageGlideResult() {
    }

    static RequestBuilder<Drawable> targetSize(
            RequestBuilder<Drawable> builder, PowerImageRequestConfig request) {
        if (request.width > 0 && request.height > 0) {
            return builder.override(request.width, request.height)
                    .downsample(DownsampleStrategy.CENTER_INSIDE);
        }
        return builder;
    }

    static void submit(
            final RequestManager requestManager,
            RequestBuilder<Drawable> builder,
            final PowerImageRequestConfig request,
            final PowerImageLoaderProtocol.PowerImageResponse response) {
        final long startedAtNanos = SystemClock.elapsedRealtimeNanos();
        PowerImageDiagnostics.debug(
                "glide_submit",
                request.requestId,
                "target=" + request.width + "x" + request.height);
        final FutureTarget<Drawable> target = targetSize(builder, request)
                .listener(new RequestListener<Drawable>() {
                    @Override
                    public boolean onLoadFailed(
                            @Nullable GlideException e,
                            Object model,
                            Target<Drawable> target,
                            boolean isFirstResource) {
                        PowerImageDiagnostics.error(
                                "glide_failed",
                                request.requestId,
                                "elapsedMs="
                                        + PowerImageDiagnostics.elapsedMillis(startedAtNanos),
                                e);
                        response.onResult(PowerImageResult.genFailRet(
                                "Native加载失败: "
                                        + (e != null ? e.getMessage() : "null")));
                        return true;
                    }

                    @Override
                    public boolean onResourceReady(
                            Drawable resource,
                            Object model,
                            Target<Drawable> target,
                            DataSource dataSource,
                            boolean isFirstResource) {
                        PowerImageDiagnostics.debug(
                                "glide_ready",
                                request.requestId,
                                "elapsedMs="
                                        + PowerImageDiagnostics.elapsedMillis(startedAtNanos)
                                        + " source=" + dataSource
                                        + " drawable=" + resource.getClass().getSimpleName()
                                        + " size=" + resource.getIntrinsicWidth() + "x"
                                        + resource.getIntrinsicHeight()
                                        + " frames=" + frameCount(resource));
                        response.onResult(fromDrawable(resource));
                        return true;
                    }
                })
                .submit(
                        request.width <= 0 ? Target.SIZE_ORIGINAL : request.width,
                        request.height <= 0 ? Target.SIZE_ORIGINAL : request.height);
        response.onRequestHandle(new PowerImageLoaderProtocol.PowerImageRequestHandle() {
            @Override
            public void cancel() {
                requestManager.clear(target);
            }
        });
    }

    static PowerImageResult fromDrawable(Drawable resource) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                && resource instanceof AnimatedImageDrawable) {
            return PowerImageResult.genSucRet(
                    new GlideAnimatedImageDrawable(
                            (AnimatedImageDrawable) resource, false));
        }
        if (resource instanceof GifDrawable) {
            return PowerImageResult.genSucRet(
                    new GlideMultiFrameImage((GifDrawable) resource, false));
        }
        if (resource instanceof WebpDrawable) {
            return PowerImageResult.genSucRet(
                    new GlideWebpMultiFrameImage((WebpDrawable) resource, false));
        }
        if (resource instanceof BitmapDrawable) {
            return PowerImageResult.genSucRet(
                    new FlutterSingleFrameImage((BitmapDrawable) resource));
        }
        return PowerImageResult.genFailRet(
                "Native加载失败: resource: " + String.valueOf(resource));
    }

    private static int frameCount(Drawable resource) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                && resource instanceof AnimatedImageDrawable) {
            return 2;
        }
        if (resource instanceof GifDrawable) {
            return ((GifDrawable) resource).getFrameCount();
        }
        if (resource instanceof WebpDrawable) {
            return ((WebpDrawable) resource).getFrameCount();
        }
        return 1;
    }
}
