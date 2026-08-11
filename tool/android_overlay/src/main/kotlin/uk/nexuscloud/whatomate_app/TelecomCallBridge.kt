package uk.nexuscloud.whatomate_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.telecom.DisconnectCause
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallsManager
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import org.json.JSONObject

/**
 * Bridges Whatomate's WebRTC call lifecycle into Android Telecom.
 *
 * WebRTC and the Whatomate backend remain authoritative for signaling/media;
 * Telecom owns Android-level call coordination (audio focus/routes, wearables,
 * automotive and competing calls). All methods are best-effort so older or
 * vendor-modified devices continue to use the existing CallStyle fallback.
 */
object TelecomCallBridge {
    private var callsManager: CallsManager? = null
    @Volatile private var controlScope: CallControlScope? = null
    @Volatile private var payload: String = "{}"
    @Volatile private var incoming: Boolean = false
    private val adding = AtomicBoolean(false)
    private val registered = AtomicBoolean(false)

    fun initialize(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = callsManager ?: CallsManager(context.applicationContext).also { callsManager = it }
            if (registered.compareAndSet(false, true)) {
                manager.registerAppWithTelecom(CallsManager.CAPABILITY_BASELINE)
            }
        } catch (_: Throwable) {
            registered.set(false)
        }
    }

    fun reportIncoming(context: Context, rawPayload: String) {
        val json = try { JSONObject(rawPayload) } catch (_: Exception) { JSONObject() }
        val caller = sequenceOf(
            json.optString("contact_name"),
            json.optString("caller_name"),
            json.optString("caller_phone"),
        ).firstOrNull { it.isNotBlank() } ?: "Incoming Whatomate call"
        val address = json.optString("caller_phone").ifBlank { caller }
        report(context, caller, address, rawPayload, true)
    }

    fun reportOutgoing(context: Context, caller: String, address: String) {
        report(context, caller.ifBlank { address.ifBlank { "Whatomate call" } }, address, "{}", false)
    }

    private fun report(context: Context, caller: String, address: String, rawPayload: String, isIncoming: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        initialize(context)
        if (controlScope != null || !adding.compareAndSet(false, true)) return
        payload = rawPayload
        incoming = isIncoming

        val attributes = CallAttributesCompat(
            displayName = caller,
            address = Uri.parse("whatomate:${Uri.encode(address.ifBlank { caller })}"),
            direction = if (isIncoming) CallAttributesCompat.DIRECTION_INCOMING else CallAttributesCompat.DIRECTION_OUTGOING,
            callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
            callCapabilities = CallAttributesCompat.SUPPORTS_SET_INACTIVE,
        )

        launchSuspend {
            try {
                val manager = callsManager ?: return@launchSuspend
                manager.addCall(
                    callAttributes = attributes,
                    onAnswer = {
                        dispatch(context, "answer", payload)
                    },
                    onDisconnect = { cause ->
                        val action = if (incoming && cause.code == DisconnectCause.REJECTED) "decline" else "hangup"
                        dispatch(context, action, payload)
                    },
                    onSetActive = {
                        dispatch(context, "resume", payload)
                    },
                    onSetInactive = {
                        dispatch(context, "hold", payload)
                    },
                ) {
                    controlScope = this
                    adding.set(false)
                }
            } catch (_: Throwable) {
                controlScope = null
                adding.set(false)
            }
        }
    }

    fun answerFromApp() {
        val scope = controlScope ?: return
        launchSuspend { runCatching { scope.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL) } }
    }

    fun setActiveFromApp() {
        val scope = controlScope ?: return
        launchSuspend { runCatching { scope.setActive() } }
    }

    fun setInactiveFromApp() {
        val scope = controlScope ?: return
        launchSuspend { runCatching { scope.setInactive() } }
    }

    fun declineFromApp() {
        disconnect(DisconnectCause.REJECTED)
    }

    fun endFromApp() {
        disconnect(DisconnectCause.LOCAL)
    }

    fun endFromServer() {
        disconnect(DisconnectCause.REMOTE)
    }

    private fun disconnect(code: Int) {
        val scope = controlScope
        controlScope = null
        adding.set(false)
        payload = "{}"
        incoming = false
        if (scope != null) {
            launchSuspend { runCatching { scope.disconnect(DisconnectCause(code)) } }
        }
    }

    private fun dispatch(context: Context, action: String, rawPayload: String) {
        context.startActivity(Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_CALL_ACTION, action)
            putExtra(MainActivity.EXTRA_CALL_PAYLOAD, rawPayload)
        })
    }

    private fun launchSuspend(block: suspend () -> Unit) {
        thread(name = "whatomate-telecom", isDaemon = true) {
            block.startCoroutine(object : Continuation<Unit> {
                override val context = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) = Unit
            })
        }
    }
}
