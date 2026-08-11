package uk.nexuscloud.whatomate_app

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class IncomingCallActivity : Activity() {
    companion object {
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_CALLER = "caller"
        const val EXTRA_ACTION = "direct_action"
        const val CALL_NOTIFICATION_ID = 9001
        private const val MICROPHONE_PERMISSION_REQUEST = 9002
    }

    private var pendingAnswer = false
    private var subtitleView: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        TelecomCallBridge.initialize(this)

        val directAction = intent.getStringExtra(EXTRA_ACTION)
        if (directAction == "answer") {
            answerWithPermission()
            return
        }
        if (directAction == "decline") {
            TelecomCallBridge.declineFromApp()
            launchFlutter("decline")
            return
        }

        showIncomingUi()
    }

    private fun showIncomingUi() {
        val caller = intent.getStringExtra(EXTRA_CALLER).orEmpty().ifBlank { "Incoming call" }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 72, 48, 72)
            setBackgroundColor(Color.rgb(8, 12, 24))
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        }
        val title = TextView(this).apply {
            text = caller
            textSize = 30f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val subtitle = TextView(this).apply {
            text = "Whatomate voice call"
            textSize = 16f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 18, 0, 64)
        }
        subtitleView = subtitle
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val decline = Button(this).apply {
            text = "Decline"
            setOnClickListener {
                TelecomCallBridge.declineFromApp()
                launchFlutter("decline")
            }
        }
        val answer = Button(this).apply {
            text = "Answer"
            setOnClickListener { answerWithPermission() }
        }
        actions.addView(decline, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = 16 })
        actions.addView(answer, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = 16 })
        root.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(subtitle, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(actions, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(root)
    }

    private fun answerWithPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            TelecomCallBridge.answerFromApp()
            launchFlutter("answer")
            return
        }

        pendingAnswer = true
        if (subtitleView == null) showIncomingUi()
        subtitleView?.text = "Microphone permission is required to answer"
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != MICROPHONE_PERMISSION_REQUEST || !pendingAnswer) return
        pendingAnswer = false
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            TelecomCallBridge.answerFromApp()
            launchFlutter("answer")
        } else {
            subtitleView?.text = "Microphone permission denied — enable it to answer calls"
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // A ringing call is intentionally not dismissed by Back; the user must
        // explicitly answer or decline it.
    }

    private fun launchFlutter(action: String) {
        getSystemService(NotificationManager::class.java).cancel(CALL_NOTIFICATION_ID)
        val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: "{}"
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_CALL_ACTION, action)
            putExtra(MainActivity.EXTRA_CALL_PAYLOAD, payload)
        })
        finish()
    }
}
