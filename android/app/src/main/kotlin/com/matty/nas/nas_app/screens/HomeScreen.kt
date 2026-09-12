package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.lifecycleScope
import com.matty.nas.nas_app.NasApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray

class HomeScreen(carContext: CarContext) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var downloads: JSONArray? = null
    private var sockets: JSONArray? = null
    private var loaded = false

    override fun onGetTemplate(): Template = runCatching { buildTemplate() }.getOrElse { e ->
        MessageTemplate.Builder("Error: ${e.javaClass.simpleName}: ${e.message}")
            .setTitle("NAS – Startup Error")
            .addAction(Action.Builder().setTitle("Retry")
                .setOnClickListener { loaded = false; invalidate() }.build())
            .build()
    }

    private fun buildTemplate(): Template {
        if (!api.isLoggedIn) {
            return MessageTemplate.Builder("Open the NAS app on your phone to log in first.")
                .setTitle("NAS")
                .addAction(
                    Action.Builder().setTitle("Retry")
                        .setOnClickListener { loaded = false; invalidate() }.build()
                )
                .build()
        }

        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                downloads = api.getDownloads()
                sockets = api.getTapoDevices()
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle("NAS")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }

        val activeCount = countActive(downloads)
        val socketsOn = countOn(sockets)
        val socketsTotal = sockets?.length() ?: 0

        val actionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder().setTitle("Refresh")
                    .setOnClickListener { loaded = false; invalidate() }.build()
            )
            .build()

        val list = ItemList.Builder()
            .addItem(
                Row.Builder()
                    .setTitle("Downloads")
                    .addText("$activeCount active")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(DownloadsScreen(carContext)) }
                    .build()
            )
            .addItem(
                Row.Builder()
                    .setTitle("Smart Sockets")
                    .addText("$socketsOn on · $socketsTotal total")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(SocketsScreen(carContext)) }
                    .build()
            )
            .addItem(
                Row.Builder()
                    .setTitle("Search & Grab")
                    .addText("Add movies and TV shows")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(SearchScreen(carContext)) }
                    .build()
            )
            .addItem(
                Row.Builder()
                    .setTitle("Videos")
                    .addText("Browse and play from Jellyfin")
                    .setBrowsable(true)
                    .setOnClickListener { screenManager.push(MediaBrowserScreen(carContext)) }
                    .build()
            )
            .build()

        return ListTemplate.Builder()
            .setTitle("NAS")
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(actionStrip)
            .setSingleList(list)
            .build()
    }

    private fun countActive(arr: JSONArray?): Int {
        arr ?: return 0
        val activeStates = setOf("downloading", "forcedDL", "metaDL", "stalledDL", "checkingDL", "allocating")
        return (0 until arr.length()).count { i ->
            arr.optJSONObject(i)?.optString("state", "") in activeStates
        }
    }

    private fun countOn(arr: JSONArray?): Int {
        arr ?: return 0
        return (0 until arr.length()).count { i ->
            arr.optJSONObject(i)?.optBoolean("is_on", false) == true
        }
    }
}
