// BridgeClient.kt — Android SDK (Kotlin)
// 自動生成於 2026-08-06，從 lib/services/mobile_bridge_client.dart 同步

package com.bridge.mobile

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

enum class BridgeConnectionState {
    DISCONNECTED, CONNECTING, CONNECTED, HANDSHAKING, READY, ERROR
}

data class BridgeConnectionEvent(val state: BridgeConnectionState, val message: String? = null)

data class BridgeMessage(val type: String, val taskId: String? = null, val payload: Map<String, Any> = emptyMap())

class BridgeClient(val host: String, val port: Int = 9123) {
    private var ws: WebSocket? = null
    private val client = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    var state: BridgeConnectionState = BridgeConnectionState.DISCONNECTED
        private set

    private val messageHandlers = mutableListOf<(BridgeMessage) -> Unit>()
    private val stateHandlers = mutableListOf<(BridgeConnectionEvent) -> Unit>()

    suspend fun connect() {
        updateState(BridgeConnectionState.CONNECTING)
        val url = "ws://$host:$port"

        suspendCancellableCoroutine<Unit> { cont ->
            val request = Request.Builder().url(url).build()
            ws = client.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    updateState(BridgeConnectionState.CONNECTED)
                    sendHello()
                    updateState(BridgeConnectionState.HANDSHAKING)
                    cont.resume(Unit)
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    val json = JSONObject(text)
                    val type = json.optString("type")
                    val taskId = json.optString("taskId", "")
                        .takeIf { it.isNotEmpty() }
                    val payload = json.optJSONObject("payload")?.let { obj ->
                        obj.keys().asSequence().associateWith { obj.opt(it) }
                    } ?: emptyMap()

                    val msg = BridgeMessage(type, taskId, payload)
                    fireMessage(msg)

                    if (type == "hello_ack") {
                        updateState(BridgeConnectionState.READY)
                    }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    updateState(BridgeConnectionState.ERROR)
                    reconnect()
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(1000, null)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    updateState(BridgeConnectionState.DISCONNECTED)
                }
            })
        }
    }

    fun disconnect() {
        ws?.close(1000, "client closing")
        ws = null
        updateState(BridgeConnectionState.DISCONNECTED)
    }

    private fun sendHello() {
        val deviceId = UUID.randomUUID().toString()
        val hello = JSONObject().apply {
            put("type", "hello")
            put("deviceId", deviceId)
            put("platform", "android")
            put("appVersion", "1.0.0")
        }
        ws?.send(hello.toString())
    }

    fun sendTask(
        taskType: String,
        payload: Map<String, Any>,
        taskId: String = UUID.randomUUID().toString()
    ) {
        val msg = JSONObject().apply {
            put("type", "task.run")
            put("taskId", taskId)
            put("taskType", taskType)
            put("payload", JSONObject(payload))
        }
        ws?.send(msg.toString())
    }

    fun cancelTask(taskId: String) {
        val msg = JSONObject().apply {
            put("type", "task.cancel")
            put("taskId", taskId)
        }
        ws?.send(msg.toString())
    }

    private fun reconnect() {
        // 簡化版：用 coroutine 排程重連
        Thread {
            Thread.sleep(3000)
            try {
                connect()
            } catch (_: Throwable) {}
        }.start()
    }

    fun onMessage(handler: (BridgeMessage) -> Unit) {
        messageHandlers.add(handler)
    }

    fun onStateChange(handler: (BridgeConnectionEvent) -> Unit) {
        stateHandlers.add(handler)
    }

    private fun fireMessage(message: BridgeMessage) {
        messageHandlers.forEach { it(message) }
    }

    private fun updateState(newState: BridgeConnectionState) {
        state = newState
        val event = BridgeConnectionEvent(newState)
        stateHandlers.forEach { it(event) }
    }
}
