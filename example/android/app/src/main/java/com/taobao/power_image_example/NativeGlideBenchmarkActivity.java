package com.taobao.power_image_example;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.ScrollView;

import androidx.annotation.Nullable;

import com.bumptech.glide.Glide;
import com.bumptech.glide.load.engine.DiskCacheStrategy;

/** Pure Android Glide baseline for the 20-GIPHY steady-state benchmark. */
public final class NativeGlideBenchmarkActivity extends Activity {
    private static final String[] ASSETS = {
            "giphy_17_l0HlTF1SDqER7VBCM.webp",
            "giphy_01_IRFQYGCokErS0.webp",
            "giphy_03_KG4PMQ0jyimywxNt8i.webp",
            "giphy_12_OhkMiKX0uMmLC.webp",
            "giphy_15_3oEjI6SIIHBdRxXI40.webp",
            "giphy_02_3ohhwFhUCOXOJfuttC.webp",
            "giphy_05_xThuWu82QD3pj4wvEQ.webp",
            "giphy_13_nv99yd56AMNDa.webp",
            "giphy_16_FDBoszbe5ZVmY8nj8E.webp",
            "giphy_20_PaSSGJlzQCwTlvG29p.webp",
            "giphy_07_51LroAULHlkqY.webp",
            "giphy_11_4EFt4UAegpqTy3nVce.webp",
            "giphy_18_AWNxDbtHGIJDW.webp",
            "giphy_09_BcQDiC3iLcbjG.webp",
            "giphy_06_OwlW7RLoPdPCB2MNQ8.webp",
            "giphy_08_T8Dhl1KPyzRqU.webp",
            "giphy_19_brEis8EBTBO4flSV8i.webp",
            "giphy_10_6LygV2CaXxxaDDCopf.webp",
            "giphy_14_8TkagzJHXLWmI.webp",
            "giphy_04_11ASZtb7vdJagM.webp",
    };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WrapLayout wrap = new WrapLayout();
        wrap.setBackgroundColor(Color.BLACK);

        for (String asset : ASSETS) {
            ImageView image = new ImageView(this);
            image.setAdjustViewBounds(true);
            image.setScaleType(ImageView.ScaleType.FIT_CENTER);
            wrap.addView(image, new ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT));

            String uri = "file:///android_asset/flutter_assets/assets/benchmark/"
                    + "giphy_webp/" + asset;
            Glide.with(this)
                    .load(Uri.parse(uri))
                    .diskCacheStrategy(DiskCacheStrategy.NONE)
                    .skipMemoryCache(true)
                    .dontAnimate()
                    .into(image);
        }

        ScrollView root = new ScrollView(this);
        root.setFillViewport(true);
        root.setBackgroundColor(Color.BLACK);
        root.addView(wrap, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);
    }

    private final class WrapLayout extends ViewGroup {
        WrapLayout() {
            super(NativeGlideBenchmarkActivity.this);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int widthLimit = MeasureSpec.getSize(widthMeasureSpec);
            int lineWidth = 0;
            int lineHeight = 0;
            int contentHeight = 0;
            for (int index = 0; index < getChildCount(); index++) {
                View child = getChildAt(index);
                measureChild(child, widthMeasureSpec, heightMeasureSpec);
                if (lineWidth > 0 && lineWidth + child.getMeasuredWidth() > widthLimit) {
                    contentHeight += lineHeight;
                    lineWidth = 0;
                    lineHeight = 0;
                }
                lineWidth += child.getMeasuredWidth();
                lineHeight = Math.max(lineHeight, child.getMeasuredHeight());
            }
            contentHeight += lineHeight;
            setMeasuredDimension(
                    resolveSize(widthLimit, widthMeasureSpec),
                    resolveSize(contentHeight, heightMeasureSpec));
        }

        @Override
        protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
            int widthLimit = right - left;
            int x = 0;
            int y = 0;
            int lineHeight = 0;
            for (int index = 0; index < getChildCount(); index++) {
                View child = getChildAt(index);
                if (x > 0 && x + child.getMeasuredWidth() > widthLimit) {
                    y += lineHeight;
                    x = 0;
                    lineHeight = 0;
                }
                child.layout(x, y, x + child.getMeasuredWidth(), y + child.getMeasuredHeight());
                x += child.getMeasuredWidth();
                lineHeight = Math.max(lineHeight, child.getMeasuredHeight());
            }
        }
    }
}
