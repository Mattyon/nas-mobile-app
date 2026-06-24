package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.lifecycleScope
import com.matty.nas.nas_app.NasApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

class GrabScreen(
    carContext: CarContext,
    private val item: JSONObject
) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var grabbing = false
    private var grabbed = false
    private var error: String? = null

    override fun onGetTemplate(): Template {
        val rawTitle = item.optString("title", "Unknown")
        val year = item.optString("year", "")
        val title = if (year.isNotEmpty()) "$rawTitle ($year)" else rawTitle
        val type = item.optString("type", "movie")

        if (grabbed) {
            return MessageTemplate.Builder("Added to downloads.")
                .setTitle(title.take(60))
                .addAction(
                    Action.Builder().setTitle("Done")
                        .setOnClickListener { screenManager.popToRoot() }.build()
                )
                .build()
        }

        if (grabbing) {
            return MessageTemplate.Builder("Adding to downloads...")
                .setTitle(title.take(60))
                .build()
        }

        val errText = error
        if (errText != null) {
            return MessageTemplate.Builder(errText)
                .setTitle(title.take(60))
                .setHeaderAction(Action.BACK)
                .addAction(
                    Action.Builder().setTitle("Try Again")
                        .setOnClickListener { error = null; invalidate() }.build()
                )
                .build()
        }

        fun grab(tier: String) {
            grabbing = true
            error = null
            invalidate()
            lifecycleScope.launch(Dispatchers.IO) {
                val tmdbId = if (type == "movie") item.optInt("tmdbId", 0).takeIf { it > 0 } else null
                val tvdbId = if (type == "tv") item.optInt("tvdbId", 0).takeIf { it > 0 } else null
                val result = runCatching { api.grab(type, tmdbId, tvdbId, tier) }.getOrNull()
                grabbing = false
                if (result != null) grabbed = true
                else error = "Failed to add. Check your connection and try again."
                invalidate()
            }
        }

        val list = ItemList.Builder()
            .addItem(
                Row.Builder()
                    .setTitle("Fast")
                    .addText("First available release")
                    .setOnClickListener { grab("fast") }
                    .build()
            )
            .addItem(
                Row.Builder()
                    .setTitle("Balanced")
                    .addText("Good quality, verified source")
                    .setOnClickListener { grab("balanced") }
                    .build()
            )
            .addItem(
                Row.Builder()
                    .setTitle("Best")
                    .addText("Highest quality available")
                    .setOnClickListener { grab("best") }
                    .build()
            )
            .build()

        return ListTemplate.Builder()
            .setTitle(title.take(60))
            .setHeaderAction(Action.BACK)
            .setSingleList(list)
            .build()
    }
}
