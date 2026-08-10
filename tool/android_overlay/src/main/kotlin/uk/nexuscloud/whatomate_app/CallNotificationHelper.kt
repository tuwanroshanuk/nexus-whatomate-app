package uk.nexuscloud.whatomate_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import org.json.JSONObject

object CallNotificationHelper {
    private const val CALL_CHANNEL_ID = "whatomate_calls"
    private const val CALL_CHANNEL_NAME = "Whatomate calls"
    private const val ACTIVE_CALL_CHANNEL_ID = "whatomate_active_calls"
    private const val ACTIVE_CALL_CHANNEL_NAME = "Active Whatomate calls"
    private const val ACTIVE_CALL_NOTIFICATION_ID = 9003

    fun showIncomingCall(context: Context, payload: String) {
        createCallChannel(context)
        val json = try { JSONObject(payload) } catch (_: Exception) { JSONObject() }
        val caller = sequenceOf(
            json.optString("contact_name"),
            json.optString("caller_name"),
            json.optString("caller_phone"),
        ).firstOrNull { it.isNotBlank() } ?: "Incoming call"

        val fullScreen = callActivityIntent(context, payload, caller, null, 9100)
        val answer = callActivityIntent(context, payload, caller, "answer", 9101)
        val decline = callActivityIntent(context, payload, caller, "decline", 9102)
        val person = Person.Builder().setName(caller).setImportant(true).build()

        val notification = NotificationCompat.Builder(context, CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(caller)
            .setContentText("Incoming Whatomate call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, decline, answer))
            .addPerson(person)
            .build()

        context.getSystemService(NotificationManager::class.java)
            .notify(IncomingCallActivity.CALL_NOTIFICATION_ID, notification)
    }

    fun showOngoingCall(context: Context, caller: String, status: String) {
        createActiveCallChannel(context)
        // Once a call is connected/being placed, the ringing notification is
        // no longer authoritative. Replace it with the persistent active-call
        // notification so Home/lock-screen users retain a way back and a
        // direct Hang Up action.
        cancelIncomingCall(context)

        val displayName = caller.ifBlank { "Whatomate call" }
        val open = mainActivityIntent(context, null, 9200)
        val hangup = mainActivityIntent(context, "hangup", 9201)
        val person = Person.Builder().setName(displayName).setImportant(true).build()
        val text = status.ifBlank { "Call in progress" }

        val builder = NotificationCompat.Builder(context, ACTIVE_CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle(displayName)
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .addPerson(person)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(NotificationCompat.CallStyle.forOngoingCall(person, hangup))
        } else {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Hang up",
                hangup,
            )
        }

        context.getSystemService(NotificationManager::class.java)
            .notify(ACTIVE_CALL_NOTIFICATION_ID, builder.build())
    }

    fun cancelIncomingCall(context: Context) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(IncomingCallActivity.CALL_NOTIFICATION_ID)
    }

    fun cancelOngoingCall(context: Context) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(ACTIVE_CALL_NOTIFICATION_ID)
    }

    fun createCallChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CALL_CHANNEL_ID) != null) return
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            CALL_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming Whatomate voice calls"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 450, 250, 450)
            setSound(sound, audioAttributes)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun createActiveCallChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(ACTIVE_CALL_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            ACTIVE_CALL_CHANNEL_ID,
            ACTIVE_CALL_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Ongoing Whatomate voice calls"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun mainActivityIntent(
        context: Context,
        directAction: String?,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (directAction != null) {
                putExtra(MainActivity.EXTRA_CALL_ACTION, directAction)
                putExtra(MainActivity.EXTRA_CALL_PAYLOAD, "{}")
            }
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun callActivityIntent(
        context: Context,
        payload: String,
        caller: String,
        directAction: String?,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, IncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(IncomingCallActivity.EXTRA_PAYLOAD, payload)
            putExtra(IncomingCallActivity.EXTRA_CALLER, caller)
            if (directAction != null) putExtra(IncomingCallActivity.EXTRA_ACTION, directAction)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
