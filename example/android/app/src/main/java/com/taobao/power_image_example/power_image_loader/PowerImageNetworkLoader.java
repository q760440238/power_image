package com.taobao.power_image_example.power_image_loader;

import android.content.Context;
import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestManager;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.request.PowerImageRequestConfig;

import java.util.Locale;

/**
 * created by Muke on 2021/7/25
 */
public class PowerImageNetworkLoader implements PowerImageLoaderProtocol {

    private Context context;

    public PowerImageNetworkLoader(Context context) {
        this.context = context;
    }

    @Override
    public void handleRequest(PowerImageRequestConfig request, PowerImageResponse response) {
        RequestManager requestManager = Glide.with(context);
        String source = request.srcString();
        if (isWebpUrl(source)) {
            PowerImageGlideResult.submitEncodedWebp(
                    requestManager, source, request, response);
            return;
        }
        PowerImageGlideResult.submit(
                requestManager,
                requestManager.asDrawable().load(source),
                request,
                response);
    }

    static boolean isWebpUrl(String source) {
        if (source == null) {
            return false;
        }
        int pathEnd = source.length();
        int queryStart = source.indexOf('?');
        if (queryStart >= 0) {
            pathEnd = queryStart;
        }
        int fragmentStart = source.indexOf('#');
        if (fragmentStart >= 0 && fragmentStart < pathEnd) {
            pathEnd = fragmentStart;
        }
        String path = source.substring(0, pathEnd);
        return path.toLowerCase(Locale.US).endsWith(".webp");
    }
}
