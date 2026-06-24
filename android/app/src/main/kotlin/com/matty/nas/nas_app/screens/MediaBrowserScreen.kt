package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.SectionedItemList
import androidx.car.app.model.Template
import androidx.lifecycle.lifecycleScope
import com.matty.nas.nas_app.NasApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import org.json.JSONObject

class MediaBrowserScreen(carContext: CarContext) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var movies: List<JSONObject> = emptyList()
    private var shows: List<JSONObject> = emptyList()
    private var loaded = false
    private var error: String? = null

    override fun onGetTemplate(): Template {
        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                val moviesDeferred = async { runCatching { api.getJellyfinMovies() }.getOrDefault(emptyList()) }
                val showsDeferred = async { runCatching { api.getJellyfinShows() }.getOrDefault(emptyList()) }
                movies = moviesDeferred.await()
                shows = showsDeferred.await()
                if (movies.isEmpty() && shows.isEmpty()) {
                    error = "Could not reach Jellyfin at ${api.jellyfinUrl}.\nCheck that the server is reachable."
                }
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle("Videos")
                .setHeaderAction(Action.BACK)
                .build()
        }

        val err = error
        if (err != null) {
            return MessageTemplate.Builder(err)
                .setTitle("Videos")
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle("Retry")
                    .setOnClickListener { loaded = false; error = null; invalidate() }.build())
                .build()
        }

        val builder = ListTemplate.Builder()
            .setTitle("Videos")
            .setHeaderAction(Action.BACK)
            .setActionStrip(ActionStrip.Builder()
                .addAction(Action.Builder().setTitle("Refresh")
                    .setOnClickListener { loaded = false; invalidate() }.build())
                .build())

        val displayMovies = movies.take(6)
        if (displayMovies.isNotEmpty()) {
            val movieList = ItemList.Builder().apply {
                displayMovies.forEachIndexed { idx, item ->
                    addItem(buildMovieRow(item, idx, displayMovies))
                }
            }.build()
            builder.addSectionedList(SectionedItemList.create(movieList, "Movies"))
        }

        if (shows.isNotEmpty()) {
            val showList = ItemList.Builder().apply {
                shows.take(6).forEach { item ->
                    addItem(buildSeriesRow(item))
                }
            }.build()
            builder.addSectionedList(SectionedItemList.create(showList, "TV Shows"))
        }

        return builder.build()
    }

    private fun buildMovieRow(item: JSONObject, idx: Int, allMovies: List<JSONObject>): Row {
        val name = item.optString("Name", "Unknown")
        val year = item.optInt("ProductionYear", 0)
        val label = if (year > 0) "$name ($year)" else name
        return Row.Builder()
            .setTitle(label)
            .addText("Tap to play")
            .setBrowsable(true)
            .setOnClickListener {
                screenManager.push(VideoPlayerScreen(carContext, allMovies, idx, api))
            }
            .build()
    }

    private fun buildSeriesRow(item: JSONObject): Row {
        val name = item.optString("Name", "Unknown")
        val year = item.optInt("ProductionYear", 0)
        val label = if (year > 0) "$name ($year)" else name
        return Row.Builder()
            .setTitle(label)
            .addText("Tap to browse episodes")
            .setBrowsable(true)
            .setOnClickListener {
                screenManager.push(EpisodeBrowserScreen(carContext, item))
            }
            .build()
    }
}
