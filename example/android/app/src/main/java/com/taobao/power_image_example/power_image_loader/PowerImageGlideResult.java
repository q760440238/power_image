package com.taobao.power_image_example.power_image_loader;

import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;

import com.bumptech.glide.integration.webp.decoder.WebpDrawable;
import com.bumptech.glide.load.resource.bitmap.DownsampleStrategy;
import com.bumptech.glide.load.resource.gif.GifDrawable;
import com.bumptech.glide.RequestBuilder;
import com.taobao.power_image.loader.FlutterSingleFrameImage;
import com.taobao.power_image.loader.PowerImageResult;
import com.taobao.power_image.request.PowerImageRequestConfig;
import com.taobao.power_image_example.GlideMultiFrameImage;
import com.taobao.power_image_example.GlideWebpMultiFrameImage;

final class PowerImageGlideResult {

    private PowerImageGlideResult() {
    }

    static RequestBuilder<Drawable> targetSize(
            RequestBuilder<Drawable> builder, PowerImageRequestConfig request) {
        if (request.width > 0 && request.height > 0) {
            return builder.override(request.width, request.height)
                    .downsample(DownsampleStrategy.AT_MOST);
        }
        return builder;
    }

    static PowerImageResult fromDrawable(Drawable resource) {
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
}
