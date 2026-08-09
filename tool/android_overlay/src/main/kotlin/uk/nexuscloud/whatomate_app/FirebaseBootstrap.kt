package uk.nexuscloud.whatomate_app

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

object FirebaseBootstrap {
    private const val PREFS = "whatomate_push"
    private const val PROJECT_ID = "project_id"
    private const val APPLICATION_ID = "application_id"
    private const val API_KEY = "api_key"
    private const val SENDER_ID = "sender_id"
    private const val TOKEN = "fcm_token"

    fun configure(
        context: Context,
        projectId: String,
        applicationId: String,
        apiKey: String,
        senderId: String,
    ): FirebaseApp? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(PROJECT_ID, projectId)
            .putString(APPLICATION_ID, applicationId)
            .putString(API_KEY, apiKey)
            .putString(SENDER_ID, senderId)
            .apply()
        return ensure(context)
    }

    fun ensure(context: Context): FirebaseApp? {
        try {
            return FirebaseApp.getInstance()
        } catch (_: IllegalStateException) {
            // Initialize manually below. This intentionally avoids requiring a
            // google-services.json file in the repository.
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val projectId = prefs.getString(PROJECT_ID, null) ?: return null
        val applicationId = prefs.getString(APPLICATION_ID, null) ?: return null
        val apiKey = prefs.getString(API_KEY, null) ?: return null
        val senderId = prefs.getString(SENDER_ID, null) ?: return null

        val options = FirebaseOptions.Builder()
            .setProjectId(projectId)
            .setApplicationId(applicationId)
            .setApiKey(apiKey)
            .setGcmSenderId(senderId)
            .build()
        return FirebaseApp.initializeApp(context, options)
    }

    fun saveToken(context: Context, token: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(TOKEN, token).apply()
    }

    fun savedToken(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(TOKEN, null)
}
