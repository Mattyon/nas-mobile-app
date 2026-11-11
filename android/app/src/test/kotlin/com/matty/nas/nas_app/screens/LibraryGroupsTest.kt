package com.matty.nas.nas_app.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryGroupsTest {

    private fun names(n: Int) = (0 until n).map { i -> "${'A' + (i * 26 / n)}title $i" }

    @Test fun fitsTheLimitNoGroups() {
        assertTrue(LibraryGroups.split(names(6), 6).isEmpty())
        assertTrue(LibraryGroups.split(names(52), 100).isEmpty())
    }

    @Test fun everyTitleIsInExactlyOneGroup() {
        for (n in listOf(7, 35, 52, 99, 500)) for (limit in listOf(2, 6, 12)) {
            if (n <= limit) continue
            val g = LibraryGroups.split(names(n), limit)
            assertTrue("$n/$limit: ${g.size} groups", g.size <= limit)
            assertEquals(0, g.first().from)
            assertEquals(n, g.last().to)
            g.zipWithNext().forEach { (a, b) -> assertEquals(a.to, b.from) }
        }
    }

    @Test fun fiftyTwoMoviesInSixGroupsOfAtMostNine() {
        val g = LibraryGroups.split(names(52), 6)
        assertEquals(6, g.size)
        assertTrue(g.all { it.size <= 9 })
    }

    @Test fun labels() {
        assertEquals("A – C", LibraryGroups.label("avatar", "Casablanca"))
        assertEquals("Sa – Sh", LibraryGroups.label("Saw", "sherlock"))
        assertEquals("St", LibraryGroups.label("Star Wars", "Step by Step"))
        assertEquals("# – B", LibraryGroups.label("12 Angry Men", "Braveheart"))
    }

    @Test fun plurals() {
        assertEquals("1 movie", LibraryGroups.count(1, "movie", "movies"))
        assertEquals("9 movies", LibraryGroups.count(9, "movie", "movies"))
    }

    private data class T(val name: String, val sort: String = "")

    private fun keys(vararg t: T) =
        LibraryGroups.entries(t.toList(), { it.name }, { it.sort }).map { it.key to it.item.name }

    @Test fun titleWithAnArticleIsUnderBothLetters() {
        val e = keys(T("The Big Bang Theory", "big bang theory"), T("Avatar", "avatar"),
            T("A Quiet Place", "quiet place"), T("Theodore Rex", "theodore rex"), T("Up", "up"))
        assertEquals(listOf(
            "A Quiet Place" to "A Quiet Place",
            "avatar" to "Avatar",
            "big bang theory" to "The Big Bang Theory",
            "quiet place" to "A Quiet Place",
            "The Big Bang Theory" to "The Big Bang Theory",
            "theodore rex" to "Theodore Rex",
            "up" to "Up",
        ), e)
    }

    @Test fun withoutSortNameTheArticleIsDroppedForTheFirstKey() {
        assertEquals(listOf("Matrix" to "The Matrix", "The Matrix" to "The Matrix"), keys(T("The Matrix")))
    }

    @Test fun noDuplicateWhenTheSortNameKeepsTheArticle() {
        assertEquals(1, keys(T("The Office", "The Office")).size)
    }

    @Test fun accentsSortWithTheirLetter() {
        val e = keys(T("Zorro"), T("Čtyři v tom"), T("Casablanca"), T("Dune")).map { it.second }
        assertEquals(listOf("Casablanca", "Čtyři v tom", "Dune", "Zorro"), e)
    }
}
