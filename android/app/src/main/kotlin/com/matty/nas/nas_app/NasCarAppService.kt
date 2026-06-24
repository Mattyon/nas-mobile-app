package com.matty.nas.nas_app

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator
import com.matty.nas.nas_app.screens.HomeScreen

class NasCarAppService : CarAppService() {

    override fun createHostValidator() = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent) = HomeScreen(carContext)
    }
}
