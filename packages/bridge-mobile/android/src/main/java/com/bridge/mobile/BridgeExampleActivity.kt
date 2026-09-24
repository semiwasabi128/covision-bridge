// ExampleApp.kt — Android 範例
// 自動生成於 2026-08-06

package com.bridge.mobile.example

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.bridge.mobile.BridgeClient
import com.bridge.mobile.BridgeMessage
import com.bridge.mobile.BridgeTokens

class ExampleActivity : AppCompatActivity() {
    private lateinit var client: BridgeClient
    private lateinit var statusView: TextView
    private lateinit var connectButton: Button
    private lateinit var sendButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_example)

        statusView = findViewById(R.id.status)
        connectButton = findViewById(R.id.connect_button)
        sendButton = findViewById(R.id.send_button)

        // 套用 design tokens
        findViewById<android.view.View>(R.id.root).setBackgroundColor(BridgeTokens.CANVAS)
        statusView.setTextColor(BridgeTokens.TEXT_PRIMARY)
        connectButton.setBackgroundColor(BridgeTokens.ACCENT_BLUE)
        sendButton.setBackgroundColor(BridgeTokens.ACCENT_GREEN)

        // 初始化 client
        client = BridgeClient(host = "192.168.1.100", port = 9123)

        client.onStateChange { event ->
            runOnUiThread {
                statusView.text = "狀態: ${event.state}" + (event.message?.let { " - $it" } ?: "")
            }
        }

        client.onMessage { message ->
            runOnUiThread {
                when (message.type) {
                    "task.complete" -> {
                        statusView.text = "任務完成: ${message.payload}"
                    }
                    "task.progress" -> {
                        val progress = message.payload["progress"] as? Double ?: 0.0
                        statusView.text = "進度: ${(progress * 100).toInt()}%"
                    }
                }
            }
        }

        connectButton.setOnClickListener {
            statusView.text = "連線中..."
            lifecycleScope.launch {
                try {
                    client.connect()
                } catch (e: Exception) {
                    statusView.text = "連線失敗: ${e.message}"
                }
            }
        }

        sendButton.setOnClickListener {
            client.sendTask(
                taskType = "browser.navigate",
                payload = mapOf("url" to "https://example.com")
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        client.disconnect()
    }
}
