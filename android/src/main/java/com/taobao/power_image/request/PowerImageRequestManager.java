package com.taobao.power_image.request;

import static com.taobao.power_image.request.PowerImageBaseRequest.RENDER_TYPE_EXTERNAL;
import static com.taobao.power_image.request.PowerImageBaseRequest.RENDER_TYPE_TEXTURE;

import com.taobao.power_image.PowerImageEngineContext;
import com.taobao.power_image.PowerImageDiagnostics;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.view.TextureRegistry;

/**
 * created by Muke on 2021/7/21
 */
public class PowerImageRequestManager {

    private final PowerImageEngineContext engineContext;

    private Map<String, PowerImageBaseRequest> requests;
    private final Map<String, Boolean> animationStates;
    private WeakReference<TextureRegistry> textureRegistryWrf;

    public PowerImageRequestManager(PowerImageEngineContext context) {
        engineContext = context;
        requests = new HashMap<>();
        animationStates = new HashMap<>();
    }

    public void configWithTextureRegistry(TextureRegistry textureRegistry) {
        this.textureRegistryWrf = new WeakReference<>(textureRegistry);
    }

    public List<Map<String, Object>> configRequestsWithArguments(List<Map<String, Object>> list) {
        List<Map<String, Object>> results = new ArrayList<>();
        if (list == null || list.isEmpty()) {
            return results;
        }
        for (int i = 0; i < list.size(); i++) {
            Object item = list.get(i);
            if (!(item instanceof Map)) {
                PowerImageDiagnostics.error(
                        "request_config_ignored", null, "reason=null_arguments", null);
                continue;
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> arguments = (Map<String, Object>) item;
            Object renderTypeValue = arguments.get("renderingType");
            String renderType = renderTypeValue instanceof String
                    ? (String) renderTypeValue : null;
            PowerImageBaseRequest request;
            if (RENDER_TYPE_EXTERNAL.equals(renderType)) {
                request = new PowerImageExternalRequest(engineContext, arguments);
            } else if (RENDER_TYPE_TEXTURE.equals(renderType)) {
                TextureRegistry textureRegistry = textureRegistryWrf != null
                        ? textureRegistryWrf.get() : null;
                request = new PowerImageTextureRequest(
                        engineContext, arguments, textureRegistry);
            } else {
                Object requestIdValue = arguments.get("uniqueKey");
                PowerImageDiagnostics.error(
                        "request_config_ignored",
                        requestIdValue instanceof String
                                ? (String) requestIdValue : null,
                        "reason=invalid_render_type",
                        null);
                continue;
            }
            PowerImageBaseRequest previous = requests.put(request.requestId, request);
            if (previous != null && previous != request) {
                previous.stopTask();
                PowerImageDiagnostics.debug(
                        "request_replaced", request.requestId, null);
            }
            Boolean animationActive = animationStates.get(request.requestId);
            if (animationActive != null) {
                request.setAnimationActive(animationActive);
            }
            boolean success = request.configTask();
            Map<String, Object> requestInfo = request.encode();
            requestInfo.put("success", success);
            results.add(requestInfo);
        }
        return results;
    }

    public void startLoadingWithArguments(List arguments) {
        if (arguments == null || arguments.isEmpty()) {
            return;
        }
        for (int i = 0; i < arguments.size(); i++) {
            Object item = arguments.get(i);
            if (!(item instanceof Map)) {
                continue;
            }
            Object requestIdValue = ((Map) item).get("uniqueKey");
            if (!(requestIdValue instanceof String)) {
                continue;
            }
            String requestId = (String) requestIdValue;
            PowerImageBaseRequest request = requests.get(requestId);
            if (request != null) {
                request.startLoading();
            } else {
                PowerImageDiagnostics.debug(
                        "request_start_ignored", requestId, "reason=not_configured");
            }
        }
    }

    public List<Map<String, Object>> releaseRequestsWithArguments(List arguments) {
        List<Map<String, Object>> results = new ArrayList<>();
        if (arguments == null || arguments.isEmpty()) {
            return results;
        }
        for (int i = 0; i < arguments.size(); i++) {
            Object item = arguments.get(i);
            if (!(item instanceof Map)) {
                continue;
            }
            Object requestIdValue = ((Map) item).get("uniqueKey");
            if (!(requestIdValue instanceof String)) {
                continue;
            }
            String requestId = (String) requestIdValue;
            PowerImageBaseRequest request = requests.get(requestId);
            if (request != null) {
                requests.remove(requestId);
                animationStates.remove(requestId);
                boolean success = request.stopTask();
                Map<String, Object> requestInfo = request.encode();
                requestInfo.put("success", success);
                results.add(requestInfo);
            }
        }
        return results;
    }

    public void setAnimationActive(String requestId, boolean active) {
        if (requestId == null) {
            return;
        }
        animationStates.put(requestId, active);
        PowerImageBaseRequest request = requests.get(requestId);
        if (request != null) {
            request.setAnimationActive(active);
        }
    }

    public void releaseAllRequests() {
        for (PowerImageBaseRequest request : new ArrayList<>(requests.values())) {
            request.stopTask();
        }
        requests.clear();
        animationStates.clear();
    }

    public void releaseAllRequestsForEngineDetach() {
        for (PowerImageBaseRequest request : new ArrayList<>(requests.values())) {
            request.stopTaskForEngineDetach();
        }
        requests.clear();
        animationStates.clear();
    }
}
