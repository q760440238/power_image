package com.taobao.power_image.request;

import android.content.res.Resources;
import android.text.TextUtils;

import java.util.Map;

/**
 * created by Muke on 2021/7/21
 */
public class PowerImageRequestConfig {
    public static final String RENDERING_TYPE_EXTERNAL = "external";
    public static final String RENDERING_TYPE_TEXTURE = "texture";

    public Map<String, Object> src;
    public String requestId;
    public String imageType;
    public String renderingType;
    public int width;
    public int height;
    public int originWidth;
    public int originHeight;

    @SuppressWarnings("unchecked")
    public static PowerImageRequestConfig requestConfigWithArguments(Map<String, Object> arguments) {
        Object srcValue = arguments.get("src");
        Map<String, Object> src = srcValue instanceof Map
                ? (Map<String, Object>) srcValue : null;
        String imageType = stringValue(arguments.get("imageType"));
        String renderingType = stringValue(arguments.get("renderingType"));
        float scale = Resources.getSystem().getDisplayMetrics().density;

        PowerImageRequestConfig config = new PowerImageRequestConfig();
        config.src = src;
        config.requestId = stringValue(arguments.get("uniqueKey"));
        config.imageType = imageType;
        config.renderingType = renderingType;
        config.width = dimensionInPixels(arguments.get("width"), scale);
        config.height = dimensionInPixels(arguments.get("height"), scale);
        config.originWidth = dimensionInPixels(arguments.get("width"), 1f);
        config.originHeight = dimensionInPixels(arguments.get("height"), 1f);
        return config;
    }

    static int dimensionInPixels(Object value, float density) {
        if (!(value instanceof Number) || density <= 0 || !Float.isFinite(density)) {
            return 0;
        }
        double points = ((Number) value).doubleValue();
        if (!Double.isFinite(points) || points <= 0) {
            return 0;
        }
        double pixels = points * density;
        return pixels >= Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) pixels;
    }

    public String srcString() {
        return src != null ? stringValue(src.get("src")) : null;
    }

    public boolean isExternal() {
        return TextUtils.equals(renderingType, RENDERING_TYPE_EXTERNAL);
    }

    public boolean isTexture() {
        return TextUtils.equals(renderingType, RENDERING_TYPE_TEXTURE);
    }

    private static String stringValue(Object value) {
        return value instanceof String ? (String) value : null;
    }

}
