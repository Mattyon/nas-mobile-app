package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.Row
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Template
import androidx.lifecycle.lifecycleScope
import com.matty.nas.nas_app.NasApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

class SearchScreen(carContext: CarContext) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var results: List<JSONObject> = emptyList()
    private var loading = false
    private var query = ""
    private var searched = false

    private val searchCallback = object : SearchTemplate.SearchCallback {
        override fun onSearchTextChanged(text: String) {}

        override fun onSearchSubmitted(text: String) {
            if (text.isBlank()) return
            query = text
            loading = true
            results = emptyList()
            searched = true
            invalidate()
            lifecycleScope.launch(Dispatchers.IO) {
                val res = api.search(text)
                val arr = res?.optJSONArray("results")
                results = if (arr != null) {
                    (0 until arr.length()).mapNotNull { arr.optJSONObject(it) }
                } else emptyList()
                loading = false
                invalidate()
            }
        }
    }

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()

        when {
            loading -> listBuilder.setNoItemsMessage("Searching...")
            !searched -> listBuilder.setNoItemsMessage("Search for movies and TV shows")
            results.isEmpty() -> listBuilder.setNoItemsMessage("No results for \"$query\"")
            else -> results.take(6).forEach { item ->
                val title = item.optString("title", "Unknown")
                val year = item.optString("year", "")
                val type = item.optString("type", "movie")
                val display = if (year.isNotEmpty()) "$title ($year)" else title
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle(display)
                        .addText(if (type == "movie") "Movie" else "TV Show")
                        .setBrowsable(true)
                        .setOnClickListener { screenManager.push(GrabScreen(carContext, item)) }
                        .build()
                )
            }
        }

        return SearchTemplate.Builder(searchCallback)
            .setHeaderAction(Action.BACK)
            .setInitialSearchText(query)
            .setShowKeyboardByDefault(true)
            .setItemList(listBuilder.build())
            .build()
    }
}
