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
import org.json.JSONObject

class DownloadsScreen(carContext: CarContext) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var downloads: JSONArray? = null
    private var loaded = false

    override fun onGetTemplate(): Template {
        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                downloads = api.getDownloads()
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle("Downloads")
                .setHeaderAction(Action.BACK)
                .build()
        }

        val arr = downloads ?: JSONArray()
        val items = (0 until arr.length())
            .mapNotNull { arr.optJSONObject(it) }
            .filter { stateGroup(it.optString("state")) < 5 }
            .sortedBy { stateGroup(it.optString("state")) }
            .take(6)

        val actionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder().setTitle("Pause All")
                    .setOnClickListener {
                        lifecycleScope.launch(Dispatchers.IO) {
                            api.pauseAll()
                            loaded = false
                            invalidate()
                        }
                    }.build()
            )
            .build()

        val listBuilder = ItemList.Builder()
        if (items.isEmpty()) {
            listBuilder.setNoItemsMessage("No active downloads")
        } else {
            items.forEach { t ->
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle(t.optString("name", "Unknown"))
                        .addText(subtitle(t))
                        .setBrowsable(true)
                        .setOnClickListener {
                            screenManager.push(DownloadDetailScreen(carContext, t))
                        }
                        .build()
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("Downloads")
            .setHeaderAction(Action.BACK)
            .setActionStrip(actionStrip)
            .setSingleList(listBuilder.build())
            .build()
    }

    private fun stateGroup(s: String) = when (s) {
        "downloading", "forcedDL", "metaDL" -> 0
        "stalledDL", "checkingDL", "allocating" -> 1
        "queuedDL" -> 2
        "pausedDL" -> 3
        "uploading", "stalledUP", "forcedUP", "checkingUP" -> 5
        else -> 4
    }

    private fun subtitle(t: JSONObject): String {
        val pct = (t.optDouble("progress", 0.0) * 100).toInt()
        val speed = t.optDouble("dlspeed_mbs", 0.0)
        return when (t.optString("state", "")) {
            "downloading", "forcedDL" -> "$pct%  ·  $speed MB/s"
            "stalledDL" -> "$pct%  ·  Stalled"
            "metaDL" -> "Fetching metadata"
            "checkingDL" -> "Checking ($pct%)"
            "allocating" -> "Allocating"
            "queuedDL" -> "Queued"
            "pausedDL" -> "$pct%  ·  Paused"
            else -> t.optString("state", "Unknown")
        }
    }
}

class DownloadDetailScreen(
    carContext: CarContext,
    private val torrent: JSONObject
) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var cancelled = false

    override fun onGetTemplate(): Template {
        val name = torrent.optString("name", "Unknown")
        val hash = torrent.optString("hash", "")

        if (cancelled) {
            return MessageTemplate.Builder("Download cancelled.")
                .setTitle(name.take(60))
                .addAction(
                    Action.Builder().setTitle("Back")
                        .setOnClickListener { screenManager.pop() }.build()
                )
                .build()
        }

        return MessageTemplate.Builder("Cancel and delete this download?")
            .setTitle(name.take(60))
            .setHeaderAction(Action.BACK)
            .addAction(
                Action.Builder().setTitle("Cancel Download")
                    .setOnClickListener {
                        lifecycleScope.launch(Dispatchers.IO) {
                            api.cancelDownload(hash)
                            cancelled = true
                            invalidate()
                        }
                    }.build()
            )
            .addAction(
                Action.Builder().setTitle("Keep")
                    .setOnClickListener { screenManager.pop() }.build()
            )
            .build()
    }
}
