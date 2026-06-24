package com.matty.nas.nas_app

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

private const val TAG = "NasAA"

class NasApiClient(private val context: Context) {

    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .build()

    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    private val flutterPrefs
        get() = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    // Reads flutter_secure_storage (EncryptedSharedPreferences) to re-login when JWT expires.
    private val securePrefs by lazy {
        runCatching {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context, "FlutterSecureStorage", masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }.getOrNull()
    }

    val baseUrl: String
        get() = flutterPrefs.getString("flutter.baseUrl", DEFAULT_URL) ?: DEFAULT_URL

    private var token: String?
        get() = flutterPrefs.getString("flutter.aa_token", null)?.takeIf { it.isNotEmpty() }
        set(value) { flutterPrefs.edit().putString("flutter.aa_token", value ?: "").apply() }

    val isLoggedIn: Boolean get() = token != null

    // ----- internal HTTP helpers -----

    private fun getJson(path: String, retried: Boolean = false): JSONObject? {
        val tok = token ?: return null
        val resp = runCatching {
            http.newCall(
                Request.Builder().url("$baseUrl$path")
                    .header("Authorization", "Bearer $tok").get().build()
            ).execute()
        }.getOrNull() ?: return null
        if (resp.code == 401 && !retried && tryRelogin()) return getJson(path, true)
        if (!resp.isSuccessful) return null
        return resp.body?.string()?.let { runCatching { JSONObject(it) }.getOrNull() }
    }

    private fun getJsonArray(path: String, retried: Boolean = false): JSONArray? {
        val tok = token ?: return null
        val resp = runCatching {
            http.newCall(
                Request.Builder().url("$baseUrl$path")
                    .header("Authorization", "Bearer $tok").get().build()
            ).execute()
        }.getOrNull() ?: return null
        if (resp.code == 401 && !retried && tryRelogin()) return getJsonArray(path, true)
        if (!resp.isSuccessful) return null
        return resp.body?.string()?.let { runCatching { JSONArray(it) }.getOrNull() }
    }

    private fun post(path: String, body: JSONObject? = null, retried: Boolean = false): JSONObject? {
        val tok = token ?: return null
        val reqBody = (body?.toString() ?: "{}").toRequestBody(jsonMedia)
        val resp = runCatching {
            http.newCall(
                Request.Builder().url("$baseUrl$path")
                    .header("Authorization", "Bearer $tok").post(reqBody).build()
            ).execute()
        }.getOrNull() ?: return null
        if (resp.code == 401 && !retried && tryRelogin()) return post(path, body, true)
        if (!resp.isSuccessful) return null
        return resp.body?.string()?.let { runCatching { JSONObject(it) }.getOrNull() }
    }

    private fun delete(path: String) {
        val tok = token ?: return
        runCatching {
            http.newCall(
                Request.Builder().url("$baseUrl$path")
                    .header("Authorization", "Bearer $tok").delete().build()
            ).execute()
        }
    }

    private fun tryRelogin(): Boolean = runCatching {
        val prefs = securePrefs ?: return false
        val user = prefs.getString("rememberUser", null) ?: return false
        val pass = prefs.getString("rememberPass", null) ?: return false
        val expStr = prefs.getString("rememberExpiry", null) ?: return false
        if (System.currentTimeMillis() > (expStr.toLongOrNull() ?: 0L)) return false
        val body = JSONObject().put("username", user).put("password", pass)
            .toString().toRequestBody(jsonMedia)
        val resp = http.newCall(
            Request.Builder().url("$baseUrl/login").post(body).build()
        ).execute()
        if (!resp.isSuccessful) return false
        val data = JSONObject(resp.body?.string() ?: return false)
        token = data.getString("token")
        true
    }.getOrDefault(false)

    // ----- public API -----

    fun getDownloads(): JSONArray? = getJsonArray("/downloads")

    fun pauseAll() { post("/qbt/pause") }
    fun resumeAll() { post("/qbt/resume") }
    fun cancelDownload(hash: String) { delete("/downloads/$hash") }

    fun getTapoDevices(): JSONArray? = getJsonArray("/tapo")
    fun tapoOn(id: String) { post("/tapo/$id/on") }
    fun tapoOff(id: String) { post("/tapo/$id/off") }

    fun search(q: String): JSONObject? =
        getJson("/search?q=${Uri.encode(q)}&type=all&lang=en")

    fun grab(type: String, tmdbId: Int?, tvdbId: Int?, tier: String): JSONObject? {
        val body = JSONObject().apply {
            put("type", type)
            put("tier", tier)
            if (tmdbId != null && tmdbId > 0) put("tmdbId", tmdbId)
            if (tvdbId != null && tvdbId > 0) put("tvdbId", tvdbId)
            put("language", "en")
        }
        return post("/grab", body)
    }

    // ----- Jellyfin -----

    private val jellyfinHttp = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    data class JellyfinAuth(val token: String, val userId: String)

    private var jellyfinAuthCache: JellyfinAuth? = null

    val jellyfinUrl: String get() =
        flutterPrefs.getString("flutter.jellyfinUrl", JELLYFIN_DEFAULT_URL) ?: JELLYFIN_DEFAULT_URL

    fun getJellyfinAuth(): JellyfinAuth? {
        jellyfinAuthCache?.let { return it }

        // Use pre-seeded token stored by the Flutter app (no re-auth needed).
        val storedToken = flutterPrefs.getString("flutter.aa_jellyfin_token", null)?.takeIf { it.isNotEmpty() }
        val storedUserId = flutterPrefs.getString("flutter.aa_jellyfin_userid", null)?.takeIf { it.isNotEmpty() }
        Log.d(TAG, "getJellyfinAuth: storedToken=${storedToken?.take(8)}, storedUserId=${storedUserId?.take(8)}, jellyfinUrl=$jellyfinUrl")
        if (storedToken != null && storedUserId != null) {
            Log.d(TAG, "getJellyfinAuth: using stored token")
            return JellyfinAuth(storedToken, storedUserId).also { jellyfinAuthCache = it }
        }

        // Fall back to re-authenticating with saved credentials.
        val prefs = securePrefs ?: return null
        val user = prefs.getString("rememberUser", null) ?: return null
        val pass = prefs.getString("rememberPass", null) ?: return null

        val body = JSONObject().put("Username", user).put("Pw", pass)
            .toString().toRequestBody(jsonMedia)
        val resp = runCatching {
            jellyfinHttp.newCall(
                Request.Builder()
                    .url("$jellyfinUrl/Users/AuthenticateByName")
                    .post(body)
                    .header("X-Emby-Authorization",
                        "MediaBrowser Client=\"NAS Auto\", Device=\"Android Auto\", DeviceId=\"nas-auto-aa\", Version=\"1.0\"")
                    .build()
            ).execute()
        }.getOrNull() ?: return null

        if (!resp.isSuccessful) return null
        val data = JSONObject(resp.body?.string() ?: return null)
        val token = data.optString("AccessToken").takeIf { it.isNotEmpty() } ?: return null
        val userId = data.optJSONObject("User")?.optString("Id") ?: return null
        return JellyfinAuth(token, userId).also { jellyfinAuthCache = it }
    }

    fun getJellyfinMovies(): List<JSONObject> = getJellyfinItems("Movie")

    fun getJellyfinShows(): List<JSONObject> = getJellyfinItems("Series")

    // Performs a Jellyfin GET; on 401 clears the cached/stored token and retries once using
    // fresh credentials from secure storage (handles expired pre-seeded tokens transparently).
    private fun jellyfinGetJson(url: String, retried: Boolean = false): JSONObject? {
        val auth = getJellyfinAuth() ?: return null
        val resp = runCatching {
            jellyfinHttp.newCall(
                Request.Builder().url(url).get()
                    .header("X-Emby-Token", auth.token).build()
            ).execute()
        }.getOrNull() ?: return null
        if (resp.code == 401 && !retried) {
            Log.d(TAG, "jellyfinGetJson: 401 – clearing cached token and retrying")
            jellyfinAuthCache = null
            flutterPrefs.edit()
                .remove("flutter.aa_jellyfin_token")
                .remove("flutter.aa_jellyfin_userid")
                .apply()
            return jellyfinGetJson(url, retried = true)
        }
        if (!resp.isSuccessful) return null
        return resp.body?.string()?.let { runCatching { JSONObject(it) }.getOrNull() }
    }

    private fun getJellyfinItems(type: String): List<JSONObject> {
        val auth = getJellyfinAuth() ?: return emptyList()
        val url = "$jellyfinUrl/Users/${auth.userId}/Items" +
            "?IncludeItemTypes=$type&Recursive=true&SortBy=SortName&SortOrder=Ascending&Limit=100" +
            "&IsMissing=false"
        val data = jellyfinGetJson(url) ?: return emptyList()
        val items = data.optJSONArray("Items") ?: return emptyList()
        return (0 until items.length()).mapNotNull { items.optJSONObject(it) }
    }

    fun getJellyfinSeriesEpisodes(seriesId: String): List<JSONObject> {
        val auth = getJellyfinAuth() ?: return emptyList()
        val url = "$jellyfinUrl/Shows/$seriesId/Episodes" +
            "?UserId=${auth.userId}&IsMissing=false" +
            "&Fields=ParentIndexNumber,IndexNumber,SeriesName" +
            "&SortBy=ParentIndexNumber,IndexNumber&SortOrder=Ascending&Limit=500"
        val data = jellyfinGetJson(url) ?: return emptyList()
        val items = data.optJSONArray("Items") ?: return emptyList()
        return (0 until items.length()).mapNotNull { items.optJSONObject(it) }
    }

    // HLS transcoding — forces H.264/AAC regardless of source codec (avoids HEVC emulator crash).
    // mediaSourceId is required by Jellyfin 10.x (returns 400 without it).
    fun getJellyfinStreamUrl(itemId: String): String {
        val auth = getJellyfinAuth()
        val token = auth?.token ?: ""
        val url = "$jellyfinUrl/Videos/$itemId/master.m3u8" +
            "?mediaSourceId=$itemId&VideoCodec=h264&AudioCodec=aac&VideoBitRate=4000000&AudioBitRate=128000&api_key=$token"
        Log.d(TAG, "getJellyfinStreamUrl: $url")
        return url
    }

    companion object {
        private const val DEFAULT_URL = "https://nas.mattyzem.com"
        private const val JELLYFIN_DEFAULT_URL = "https://jellyfin.mattyzem.com"
    }
}
