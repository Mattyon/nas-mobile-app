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

/**
 * Shows seasons for a series. Fetches all episodes once and distributes them
 * to SeasonEpisodesScreen without refetching.
 */
class EpisodeBrowserScreen(
    carContext: CarContext,
    private val series: JSONObject
) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var allEpisodes: List<JSONObject> = emptyList()
    private var loaded = false
    private var error: String? = null

    private val seriesName get() = series.optString("Name", "TV Show")

    override fun onGetTemplate(): Template {
        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                val seriesId = series.optString("Id")
                allEpisodes = runCatching { api.getJellyfinSeriesEpisodes(seriesId) }
                    .getOrDefault(emptyList())
                if (allEpisodes.isEmpty()) error = "No episodes found for $seriesName"
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle(seriesName)
                .setHeaderAction(Action.BACK)
                .build()
        }

        val err = error
        if (err != null) {
            return MessageTemplate.Builder(err)
                .setTitle(seriesName)
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle("Retry")
                    .setOnClickListener { loaded = false; error = null; invalidate() }.build())
                .build()
        }

        // Group episodes by season to count them; show one row per season.
        val seasons = allEpisodes
            .groupBy { it.optInt("ParentIndexNumber", 0) }
            .toSortedMap()

        val list = ItemList.Builder().apply {
            seasons.entries.forEach { (seasonNum, eps) ->
                val label = if (seasonNum == 0) "Specials" else "Season $seasonNum"
                addItem(Row.Builder()
                    .setTitle(label)
                    .addText("${eps.size} episode${if (eps.size != 1) "s" else ""}")
                    .setBrowsable(true)
                    .setOnClickListener {
                        screenManager.push(
                            SeasonEpisodesScreen(carContext, seriesName, seasonNum, eps, allEpisodes, api)
                        )
                    }
                    .build())
            }
        }.build()

        return ListTemplate.Builder()
            .setTitle(seriesName)
            .setHeaderAction(Action.BACK)
            .setSingleList(list)
            .build()
    }
}
