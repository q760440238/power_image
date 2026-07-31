package com.taobao.power_image_example.power_image_loader;

import android.content.Context;
import android.net.Uri;

import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestManager;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.loader.PowerImageResult;
import com.taobao.power_image.request.PowerImageRequestConfig;

import io.flutter.FlutterInjector;

/**
 * created by Muke on 2021/8/12
 */
public class PowerImageFlutterAssetLoader implements PowerImageLoaderProtocol {

    private Context context;

    public PowerImageFlutterAssetLoader(Context context) {
        this.context = context;
    }

    @Override
    public void handleRequest(PowerImageRequestConfig request, PowerImageResponse response) {
        String name = request.srcString();
        if (name == null || name.length() <= 0) {
            response.onResult(PowerImageResult.genFailRet("src 为空"));
            return;
        }
        String assetPackage = "";
        if (request.src != null) {
            assetPackage = (String) request.src.get("package");
        }
        String path;
        if (assetPackage != null && assetPackage.length() > 0) {
            path = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset(name, assetPackage);
        } else {
            path = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset(name);
        }
        if (path == null || path.length() <= 0) {
            response.onResult(PowerImageResult.genFailRet("path 为空"));
            return;
        }
        Uri asset = Uri.parse("file:///android_asset/" + path);
        RequestManager requestManager = Glide.with(context);
        PowerImageGlideResult.submit(
                requestManager,
                requestManager.asDrawable().load(asset),
                request,
                response);
    }

}
