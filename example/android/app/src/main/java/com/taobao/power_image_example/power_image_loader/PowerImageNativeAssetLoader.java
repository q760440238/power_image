package com.taobao.power_image_example.power_image_loader;

import android.content.Context;
import android.content.res.Resources;
import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestManager;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.loader.PowerImageResult;
import com.taobao.power_image.request.PowerImageRequestConfig;

/**
 * created by Muke on 2021/7/27
 */
public class PowerImageNativeAssetLoader implements PowerImageLoaderProtocol {

    private Context context;

    public PowerImageNativeAssetLoader(Context context) {
        this.context = context;
    }

    @Override
    public void handleRequest(PowerImageRequestConfig request, PowerImageResponse response) {
        Resources resources = context.getResources();
        int resourceId = 0;
        try {
            resourceId = resources.getIdentifier(request.srcString(),
                    "drawable", context.getPackageName());
        } catch (Resources.NotFoundException e) {
            // 资源未找到
            e.printStackTrace();
        }
        if (resourceId == 0) {
            response.onResult(PowerImageResult.genFailRet("资源未找到"));
            return;
        }
        RequestManager requestManager = Glide.with(context);
        PowerImageGlideResult.submit(
                requestManager,
                requestManager.asDrawable().load(resourceId),
                request,
                response);
    }
}
