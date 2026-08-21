package uk.nexuscloud.whatomate_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import org.json.JSONObject

object MessageNotificationHelper {
    private const val CHANNEL_ID = "whatomate_messages"
    private const val CHANNEL_NAME = "Whatomate messages"
    private const val GROUP_KEY = "whatomate_conversations"
    @Volatile private var activeContact: String? = null
    @Volatile private var appForeground = false

    fun showMessage(context: Context, payload: String) {
        createChannel(context)
        val json = try { JSONObject(payload) } catch (_: Exception) { JSONObject() }
        val contactId = json.optString("contact_id")
        if (contactId.isBlank()) return
        if (appForeground && activeContact == contactId) {
            return
        }

        val sender = json.optString("profile_name").ifBlank { "New message" }
        val content = json.optJSONObject("content")?.optString("body").orEmpty()
        val preview = content.ifBlank {
            when (json.optString("message_type")) {
                "image" -> "Photo"
                "video" -> "Video"
                "audio" -> "Audio message"
                "document" -> "Document"
                else -> "New WhatsApp message"
            }
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_CALL_ACTION, "open_message")
            putExtra(MainActivity.EXTRA_CALL_PAYLOAD, payload)
        }
        val requestCode = contactId.hashCode() and 0x7fffffff
        val open = PendingIntent.getActivity(
            context,
            requestCode,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(sender)
            .setContentText(preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText(preview))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setGroup(GROUP_KEY)
            .build()

        context.getSystemService(NotificationManager::class.java)
            .notify(requestCode, notification)
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Messages assigned to you in Whatomate"
                enableVibration(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
            },
        )
    }

    fun setActiveContact(contactId: String?) {
        activeContact = contactId
    }

    fun setAppForeground(foreground: Boolean) {
        appForeground = foreground
    }
}
