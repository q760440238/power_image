package com.taobao.power_image.request;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertSame;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.taobao.power_image.PowerImageEngineContext;

import org.junit.Test;

import java.lang.reflect.Field;
import java.util.Map;

import io.flutter.view.TextureRegistry;

public class PowerImageRequestManagerTest {
    @Test
    public void completedEncodedRequestIsRemovedAndStoppedImmediately() throws Exception {
        PowerImageRequestManager manager =
                new PowerImageRequestManager(mock(PowerImageEngineContext.class));
        PowerImageBaseRequest request = mock(PowerImageBaseRequest.class);
        request.requestId = "encoded-request";

        Field requestsField = PowerImageRequestManager.class.getDeclaredField("requests");
        requestsField.setAccessible(true);
        @SuppressWarnings("unchecked")
        Map<String, PowerImageBaseRequest> requests =
                (Map<String, PowerImageBaseRequest>) requestsField.get(manager);
        requests.put(request.requestId, request);
        manager.setAnimationActive(request.requestId, true);

        manager.releaseCompletedRequest(request);

        assertFalse(requests.containsKey(request.requestId));
        verify(request).stopTask();
    }

    @Test
    public void releaseGateIsScopedToOneTextureRegistryGeneration() {
        PowerImageRequestManager manager =
                new PowerImageRequestManager(mock(PowerImageEngineContext.class));
        TextureRegistry firstRegistry = mock(TextureRegistry.class);
        TextureRegistry secondRegistry = mock(TextureRegistry.class);

        manager.configWithTextureRegistry(firstRegistry);
        SurfaceProducerReleaseGate firstGate = manager.surfaceReleaseGateForTesting();
        manager.configWithTextureRegistry(firstRegistry);
        assertSame(firstGate, manager.surfaceReleaseGateForTesting());

        manager.configWithTextureRegistry(secondRegistry);
        assertNotSame(firstGate, manager.surfaceReleaseGateForTesting());
    }
}
