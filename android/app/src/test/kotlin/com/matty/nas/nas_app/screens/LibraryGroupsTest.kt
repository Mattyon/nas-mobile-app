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
}
