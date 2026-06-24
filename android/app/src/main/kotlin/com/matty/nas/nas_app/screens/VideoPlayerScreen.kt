package com.matty.nas.nas_app.screens

import android.graphics.Rect
import android.util.Log
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.matty.nas.nas_app.NasApiClient
import org.json.JSONObject

class VideoPlayerScreen(
    carContext: CarContext,
    private val items: List<JSONObject>,
    private var currentIndex: Int = 0,
    private val api: NasApiClient = NasApiClient(carContext)
) : Screen(carContext) {

    private var player: ExoPlayer? = null
    private var currentSurface: android.view.Surface? = null
    private var isPlaying = false
    private var isBuffering = false
    private var error: String? = null

    private val currentItem get() = items.getOrNull(currentIndex)

    private fun buildTitle(): String {
        val item = currentItem ?: return "Video"
        val name = item.optString("Name", "Video")
        val series = item.optString("SeriesName", "")
        val season = item.optInt("ParentIndexNumber", 0)
        val epIdx = item.optInt("IndexNumber", 0)
        return when {
            series.isNotEmpty() && epIdx > 0 -> "$series S${season}E$epIdx: $name"
            series.isNotEmpty() -> "$series: $name"
            else -> name
        }
    }

    private val surfaceCallback = object : SurfaceCallback {
        override fun onSurfaceAvailable(container: SurfaceContainer) {
            currentSurface = container.surface ?: return
            startPlayer()
        }
        override fun onSurfaceDestroyed(container: SurfaceContainer) {
            player?.setVideoSurface(null)
            currentSurface = null
        }
        override fun onVisibleAreaChanged(visibleArea: Rect) {}
        override fun onStableAreaChanged(stableArea: Rect) {}
    }

    init {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(surfaceCallback)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) { releasePlayer() }
        })
    }

    private fun startPlayer() {
        val surface = currentSurface ?: return
        val itemId = currentItem?.optString("Id") ?: return
        Log.d("NasAA", "VideoPlayerScreen.startPlayer itemId=$itemId title=${buildTitle()}")
        player?.release()
        val streamUrl = api.getJellyfinStreamUrl(itemId)
        val p = ExoPlayer.Builder(carContext).build()
        p.setVideoSurface(surface)
        p.setMediaItem(MediaItem.fromUri(streamUrl))
        p.prepare()
        p.play()
        p.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                isBuffering = false
                invalidate()
            }
            override fun onPlaybackStateChanged(state: Int) {
                isBuffering = state == Player.STATE_BUFFERING
                if (state == Player.STATE_ENDED && currentIndex + 1 < items.size) {
                    changeEpisode(currentIndex + 1)
                } else {
                    invalidate()
                }
            }
            override fun onPlayerError(err: PlaybackException) {
                Log.e("NasAA", "VideoPlayerScreen.onPlayerError: ${err.message}", err.cause)
                error = err.message ?: "Playback error"
                invalidate()
            }
        })
        player = p
        isPlaying = true
        isBuffering = true
        error = null
        invalidate()
    }

    private fun changeEpisode(newIndex: Int) {
        currentIndex = newIndex
        startPlayer()
    }

    private fun releasePlayer() {
        player?.release()
        player = null
        runCatching { carContext.getCarService(AppManager::class.java).setSurfaceCallback(null) }
    }

    override fun onGetTemplate(): Template {
        val err = error
        if (err != null) {
            return MessageTemplate.Builder(err)
                .setTitle(buildTitle().take(60))
                .setHeaderAction(Action.BACK)
                .addAction(Action.Builder().setTitle("Retry")
                    .setOnClickListener {
                        error = null
                        startPlayer()
                        invalidate()
                    }.build())
                .build()
        }

        val playPauseLabel = when {
            isBuffering -> "Buffering…"
            isPlaying   -> "Pause"
            else        -> "Play"
        }

        // NavigationTemplate action strip max 4 buttons; build conditionally based on context.
        val actionStripBuilder = ActionStrip.Builder()
        val hasMultiple = items.size > 1

        if (hasMultiple && currentIndex > 0) {
            actionStripBuilder.addAction(Action.Builder()
                .setTitle("⏮ Prev")
                .setOnClickListener { changeEpisode(currentIndex - 1) }
                .build())
        }

        actionStripBuilder.addAction(Action.Builder()
            .setTitle(playPauseLabel)
            .setOnClickListener {
                val p = player ?: return@setOnClickListener
                if (p.isPlaying) p.pause() else p.play()
            }.build())

        if (hasMultiple && currentIndex + 1 < items.size) {
            actionStripBuilder.addAction(Action.Builder()
                .setTitle("Next ⏭")
                .setOnClickListener { changeEpisode(currentIndex + 1) }
                .build())
        }

        actionStripBuilder.addAction(Action.Builder()
            .setTitle("Stop")
            .setOnClickListener {
                releasePlayer()
                screenManager.pop()
            }.build())

        return NavigationTemplate.Builder()
            .setActionStrip(actionStripBuilder.build())
            .build()
    }
}
