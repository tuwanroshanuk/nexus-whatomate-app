package uk.nexuscloud.whatomate_app

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class WhatomateMessagingService : FirebaseMessagingService() {
    override fun onCreate() {
        FirebaseBootstrap.ensure(this)
        TelecomCallBridge.initialize(this)
        CallNotificationHelper.createCallChannel(this)
        MessageNotificationHelper.createChannel(this)
        super.onCreate()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        FirebaseBootstrap.saveToken(this, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val event = message.data["event"].orEmpty()
        val payload = message.data["payload"] ?: "{}"

        when (event) {
            "new_message" -> MessageNotificationHelper.showMessage(this, payload)
            "call_transfer_waiting" -> {
                TelecomCallBridge.reportIncoming(this, payload)
                CallNotificationHelper.showIncomingCall(this, payload)
            }
            "call_transfer_connected" -> CallNotificationHelper.cancelIncomingCall(this)
            "call_transfer_completed",
            "call_transfer_abandoned",
            "call_transfer_no_answer",
            "call_transfer_reassigned",
            "call_ended" -> {
                CallNotificationHelper.cancelIncomingCall(this)
                TelecomCallBridge.endFromServer()
            }
        }
    }
}
