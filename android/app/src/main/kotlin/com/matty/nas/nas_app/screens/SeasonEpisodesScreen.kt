package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import com.matty.nas.nas_app.NasApiClient
import org.json.JSONObject

/**
 * Shows episodes for one season with in-place pagination (no extra stack depth).
 * PAGE_SIZE episodes per page; navigation rows occupy the remaining slots.
 */
class SeasonEpisodesScreen(
    carContext: CarContext,
    private val seriesName: String,
    private val seasonNumber: Int,
    private val seasonEpisodes: List<JSONObject>,  // episodes for this season only
    private val allEpisodes: List<JSONObject>,     // full series list → VideoPlayerScreen autonext
    private val api: NasApiClient
) : Screen(carContext) {

    private var pageOffset = 0

    private val seasonLabel get() = if (seasonNumber == 0) "Specials" else "Season $seasonNumber"

    companion object {
        private const val PAGE_SIZE = 5
    }

    override fun onGetTemplate(): Template {
        val hasPrev = pageOffset > 0
        val episodeSlotsOnPage = when {
            hasPrev && pageOffset + PAGE_SIZE < seasonEpisodes.size -> PAGE_SIZE - 1 // prev + N eps + next = 6
            hasPrev -> PAGE_SIZE          // prev + N eps = 6
            pageOffset + PAGE_SIZE < seasonEpisodes.size -> PAGE_SIZE // N eps + next = 6
            else -> PAGE_SIZE + 1         // last page, no nav rows needed — show up to 6
        }
        val pageEps = seasonEpisodes.drop(pageOffset).take(episodeSlotsOnPage)
        val hasNext = pageOffset + episodeSlotsOnPage < seasonEpisodes.size

        val list = ItemList.Builder().apply {
            if (hasPrev) {
                addItem(Row.Builder()
                    .setTitle("← Previous episodes")
                    .addText("Back to E${pageOffset - episodeSlotsOnPage + 1}–E$pageOffset")
                    .setBrowsable(true)
                    .setOnClickListener {
                        pageOffset = maxOf(0, pageOffset - episodeSlotsOnPage)
                        invalidate()
                    }
                    .build())
            }

            pageEps.forEach { ep ->
                val epIdx = ep.optInt("IndexNumber", 0)
                val epName = ep.optString("Name", "Episode $epIdx")
                val globalIdx = allEpisodes.indexOf(ep)
                addItem(Row.Builder()
                    .setTitle("E$epIdx: $epName")
                    .addText("Tap to play")
                    .setBrowsable(true)
                    .setOnClickListener {
                        screenManager.push(VideoPlayerScreen(carContext, allEpisodes, globalIdx, api))
                    }
                    .build())
            }

            if (hasNext) {
                val nextStart = pageOffset + episodeSlotsOnPage + 1
                val nextEnd = minOf(pageOffset + episodeSlotsOnPage + PAGE_SIZE, seasonEpisodes.size)
                addItem(Row.Builder()
                    .setTitle("More episodes →")
                    .addText("E$nextStart–E$nextEnd of ${seasonEpisodes.size}")
                    .setBrowsable(true)
                    .setOnClickListener {
                        pageOffset += episodeSlotsOnPage
                        invalidate()
                    }
                    .build())
            }
        }.build()

        return ListTemplate.Builder()
            .setTitle("$seriesName — $seasonLabel")
            .setHeaderAction(Action.BACK)
            .setSingleList(list)
            .build()
    }
}
