package com.taobao.power_image_example.power_image_loader;

import android.content.Context;
import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestManager;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.request.PowerImageRequestConfig;

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
        PowerImageGlideResult.submit(
                requestManager,
                requestManager.asDrawable().load(request.srcString()),
                request,
                response);
    }
}
