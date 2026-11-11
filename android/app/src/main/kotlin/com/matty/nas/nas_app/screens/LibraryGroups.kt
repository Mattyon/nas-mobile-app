package com.matty.nas.nas_app.screens

import java.text.Collator
import java.util.Locale

/**
 * Splits an alphabetical list into letter groups that fit the car's list limit
 * ("A – C", "D – G", ...). Pure, so it is unit-tested without a car.
 *
 * Owner, 2026-11-11: "my android auto nas app doesnt show all movies or tv shows" -- the
 * Videos screen showed only the first 6 of each. Now every title is reachable: the whole
 * list when it fits, otherwise at most [limit] groups, each opened in place.
 */
object LibraryGroups {

    /** One row: the title it is filed under ([key]) and the movie or show. */
    data class Entry<T>(val key: String, val item: T)

    private val ARTICLE = Regex("^(the|a|an)\\s+", RegexOption.IGNORE_CASE)
    private val collator = Collator.getInstance(Locale.ROOT).apply { strength = Collator.SECONDARY }

    /**
     * Every title filed under its sort name (Jellyfin drops "The", "A", "An": The Big Bang
     * Theory under B), and a title starting with an article also under its full name (under
     * T as well) -- owner, 2026-11-11: "people doesn't always know the full name".
     * Alphabetical, accents next to their letter (Č with C).
     */
    fun <T> entries(items: List<T>, name: (T) -> String, sortName: (T) -> String): List<Entry<T>> =
        items.flatMap { item ->
            val full = name(item).trim()
            val sort = sortName(item).trim().ifBlank { ARTICLE.replace(full, "") }
            if (ARTICLE.containsMatchIn(full) && !full.equals(sort, ignoreCase = true)) {
                listOf(Entry(sort, item), Entry(full, item))
            } else {
                listOf(Entry(sort, item))
            }
        }.sortedWith { a, b -> collator.compare(a.key, b.key) }

    data class Group(val from: Int, val to: Int, val label: String) {
        val size get() = to - from
    }

    /** At most [limit] contiguous groups covering indices 0 until [names].size. A group
     *  can still be larger than [limit] (more than limit² titles); it is split again when
     *  opened. Empty when the list already fits. */
    fun split(names: List<String>, limit: Int): List<Group> {
        val n = names.size
        val max = maxOf(limit, 2)
        if (n <= max) return emptyList()
        val per = (n + max - 1) / max
        return (0 until n step per).map { from ->
            val to = minOf(from + per, n)
            Group(from, to, label(names[from], names[to - 1]))
        }
    }

    /** "A – C"; two letters when both ends share the first one ("Sa – Sh"); "#" for digits. */
    fun label(first: String, last: String): String {
        val a = key(first)
        val b = key(last)
        if (a.take(1) != b.take(1)) return "${a.take(1)} – ${b.take(1)}"
        val a2 = a.take(2)
        val b2 = b.take(2)
        return if (a2 == b2) a2 else "$a2 – $b2"
    }

    private fun key(name: String): String {
        val t = name.trim()
        if (t.isEmpty()) return "?"
        if (t[0].isDigit()) return "#"
        return t.take(2).replaceFirstChar { it.uppercaseChar() }.let {
            if (it.length > 1) it[0] + it.substring(1).lowercase() else it
        }
    }

    /** "1 movie", "5 movies" -- never "movie(s)". */
    fun count(n: Int, one: String, many: String) = "$n ${if (n == 1) one else many}"
}
