package com.matty.nas.nas_app.screens

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.lifecycle.lifecycleScope
import com.matty.nas.nas_app.NasApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray

class SocketsScreen(carContext: CarContext) : Screen(carContext) {

    private val api = NasApiClient(carContext)
    private var sockets: JSONArray? = null
    private var loaded = false

    override fun onGetTemplate(): Template {
        if (!loaded) {
            lifecycleScope.launch(Dispatchers.IO) {
                sockets = api.getTapoDevices()
                loaded = true
                invalidate()
            }
            return ListTemplate.Builder()
                .setLoading(true)
                .setTitle("Smart Sockets")
                .setHeaderAction(Action.BACK)
                .build()
        }

        val arr = sockets ?: JSONArray()
        val listBuilder = ItemList.Builder()

        if (arr.length() == 0) {
            listBuilder.setNoItemsMessage("No smart sockets configured")
        } else {
            for (i in 0 until arr.length()) {
                val device = arr.optJSONObject(i) ?: continue
                val id = device.optString("id", "")
                val name = device.optString("name", "Socket")
                val isOn = device.optBoolean("is_on", false)

                listBuilder.addItem(
                    Row.Builder()
                        .setTitle(name)
                        .addText(if (isOn) "On" else "Off")
                        .setToggle(
                            Toggle.Builder { nowOn ->
                                lifecycleScope.launch(Dispatchers.IO) {
                                    if (nowOn) api.tapoOn(id) else api.tapoOff(id)
                                    device.put("is_on", nowOn)
                                    invalidate()
                                }
                            }.setChecked(isOn).build()
                        )
                        .build()
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("Smart Sockets")
            .setHeaderAction(Action.BACK)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder().setTitle("Refresh")
                            .setOnClickListener { loaded = false; invalidate() }.build()
                    ).build()
            )
            .setSingleList(listBuilder.build())
            .build()
    }
}
