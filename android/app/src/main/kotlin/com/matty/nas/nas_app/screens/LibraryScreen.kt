package com.matty.nas.nas_app.screens

import androidx.activity.OnBackPressedCallback
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
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
import org.json.JSONObject

/**
 * Every movie or every TV show in Jellyfin, alphabetical. When the list is longer than the
 * car allows, it shows letter groups (LibraryGroups); a group opens in place and Back goes
 * up a level, so the screen stack stays within Android Auto's five templates
 * (Home → TV Shows → show → season → player).
 */
class LibraryScreen(carContext: CarContext, private val shows: Boolean) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private val title = if (shows) "TV Shows" else "Movies"
    private var items: List<JSONObject> = emptyList()
    private var loaded = false
    private var error: String? = null

    /** Opened groups, outermost first; empty = the top level. */
    private val path = ArrayDeque<LibraryGroups.Group>()

    init {
        carContext.onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (path.isNotEmpty()) {
                    path.removeLast()
                    invalidate()
                } else {
                    screenManager.pop()
                }
            }
        })
    }

    private val listLimit: Int by lazy {
        runCatching {
            if (carContext.carAppApiLevel >= 2) {
                carContext.getCarService(ConstraintManager::class.java)
                    .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            } else 6
        }.getOrDefault(6)
    }

    override fun onGetTemplate(): Template {
        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                items = runCatching { if (shows) api.getJellyfinShows() else api.getJellyfinMovies() }
                    .getOrDefault(emptyList())
                error = if (items.isEmpty()) {
                    "Could not load ${title.lowercase()} from Jellyfin at ${api.jellyfinUrl}."
                } else null
                path.clear()
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder().setLoading(true).setTitle(title)
                .setHeaderAction(Action.BACK).build()
        }

        error?.let { err ->
            return MessageTemplate.Builder(err)
                .setTitle(title)
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle("Retry")
                    .setOnClickListener { loaded = false; invalidate() }.build())
                .build()
        }

        val from = path.lastOrNull()?.from ?: 0
        val to = path.lastOrNull()?.to ?: items.size
        val names = items.subList(from, to).map { sortName(it) }
        val groups = LibraryGroups.split(names, listLimit)

        val list = ItemList.Builder().apply {
            if (groups.isEmpty()) {
                for (i in from until to) addItem(if (shows) showRow(items[i]) else movieRow(i))
            } else {
                groups.forEach { g ->
                    val abs = LibraryGroups.Group(from + g.from, from + g.to, g.label)
                    addItem(Row.Builder()
                        .setTitle(g.label)
                        .addText(if (shows) LibraryGroups.count(g.size, "show", "shows")
                                 else LibraryGroups.count(g.size, "movie", "movies"))
                        .setBrowsable(true)
                        .setOnClickListener { path.addLast(abs); invalidate() }
                        .build())
                }
            }
        }.build()

        val heading = path.lastOrNull()?.let { "$title · ${it.label}" } ?: title
        return ListTemplate.Builder()
            .setTitle(heading)
            .setHeaderAction(Action.BACK)
            .setActionStrip(ActionStrip.Builder()
                .addAction(Action.Builder().setTitle("Refresh")
                    .setOnClickListener { loaded = false; invalidate() }.build())
                .build())
            .setSingleList(list)
            .build()
    }

    private fun sortName(o: JSONObject) =
        o.optString("SortName").ifBlank { o.optString("Name", "") }

    private fun label(o: JSONObject): String {
        val name = o.optString("Name", "Unknown")
        val year = o.optInt("ProductionYear", 0)
        return if (year > 0) "$name ($year)" else name
    }

    // The player gets the whole list, so "next" continues alphabetically as before.
    private fun movieRow(index: Int): Row = Row.Builder()
        .setTitle(label(items[index]))
        .addText("Tap to play")
        .setBrowsable(true)
        .setOnClickListener { screenManager.push(VideoPlayerScreen(carContext, items, index, api)) }
        .build()

    private fun showRow(o: JSONObject): Row = Row.Builder()
        .setTitle(label(o))
        .addText("Tap to browse episodes")
        .setBrowsable(true)
        .setOnClickListener { screenManager.push(EpisodeBrowserScreen(carContext, o)) }
        .build()
}
