package uk.nexuscloud.whatomate_app

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        const val EXTRA_CALL_ACTION = "whatomate_call_action"
        const val EXTRA_CALL_PAYLOAD = "whatomate_call_payload"
        private const val METHOD_CHANNEL = "uk.nexuscloud.whatomate/push"
        private const val EVENT_CHANNEL = "uk.nexuscloud.whatomate/push-events"
        private const val NOTIFICATION_PERMISSION_REQUEST = 9041
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "configure" -> {
                        val projectId = call.argument<String>("projectId").orEmpty()
                        val applicationId = call.argument<String>("applicationId").orEmpty()
                        val apiKey = call.argument<String>("apiKey").orEmpty()
                        val senderId = call.argument<String>("senderId").orEmpty()
                        if (projectId.isBlank() || applicationId.isBlank() || apiKey.isBlank() || senderId.isBlank()) {
                            result.error("firebase_config", "Firebase configuration is incomplete", null)
                            return@setMethodCallHandler
                        }
                        val app = FirebaseBootstrap.configure(this, projectId, applicationId, apiKey, senderId)
                        if (app == null) {
                            result.error("firebase_init", "Firebase could not be initialized", null)
                            return@setMethodCallHandler
                        }
                        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                            if (!task.isSuccessful) {
                                result.error("fcm_token", task.exception?.message ?: "Unable to get FCM token", null)
                                return@addOnCompleteListener
                            }
                            val token = task.result
                            FirebaseBootstrap.saveToken(this, token)
                            result.success(mapOf("configured" to true, "token" to token))
                        }
                    }
                    "getInitialCallAction" -> result.success(consumeCallAction(intent))
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "canUseFullScreenIntent" -> {
                        val manager = getSystemService(NotificationManager::class.java)
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            manager.canUseFullScreenIntent()
                        } else true
                        result.success(allowed)
                    }
                    "openFullScreenIntentSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            })
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeCallAction(intent)?.let { eventSink?.success(it) }
    }

    override fun onResume() {
        super.onResume()
        if (eventSink != null) consumeCallAction(intent)?.let { eventSink?.success(it) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun consumeCallAction(source: Intent?): Map<String, Any?>? {
        source ?: return null
        val action = source.getStringExtra(EXTRA_CALL_ACTION) ?: return null
        val rawPayload = source.getStringExtra(EXTRA_CALL_PAYLOAD) ?: "{}"
        source.removeExtra(EXTRA_CALL_ACTION)
        source.removeExtra(EXTRA_CALL_PAYLOAD)
        val parsed = mutableMapOf<String, Any?>()
        try {
            val json = JSONObject(rawPayload)
            for (key in json.keys()) parsed[key] = json.opt(key)
        } catch (_: Exception) {
            parsed["raw"] = rawPayload
        }
        return mapOf("action" to action, "payload" to parsed)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
    }
}
