package meditofoundation.medito.youtube

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class YoutubePagingTest {

    private fun page(vararg items: Int, next: String? = null) = PageResult(items.toList(), next)

    @Test
    fun aSinglePageIsReturnedAsIs() {
        assertEquals(listOf(1, 2, 3), YoutubePaging.collect(page(1, 2, 3), { it }, { error("unexpected") }))
    }

    @Test
    fun everyPageIsFollowedInOrder() {
        val pages = mapOf("b" to page(3, 4, next = "c"), "c" to page(5, next = "d"), "d" to page(6, 7))
        val fetched = mutableListOf<String>()
        val all = YoutubePaging.collect(page(1, 2, next = "b"), { it }, { token -> fetched += token; pages.getValue(token) })
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), all)
        assertEquals(listOf("b", "c", "d"), fetched)
    }

    @Test
    fun anEmptyMiddlePageDoesNotEndTheList() {
        val pages = mapOf("b" to page(next = "c"), "c" to page(9))
        assertEquals(listOf(1, 9), YoutubePaging.collect(page(1, next = "b"), { it }, { pages.getValue(it) }))
    }

    @Test
    fun aRepeatedTokenIsAFailureNotAPartialList() {
        val failure = try {
            YoutubePaging.collect(page(1, next = "b"), { it }, { page(2, next = "b") })
            null
        } catch (e: YoutubeFailure) {
            e
        }
        assertEquals("unavailable", failure?.code)
    }

    @Test
    fun anEndlessChainOfDistinctTokensStopsAtThePageLimit() {
        var n = 0
        val failure = try {
            YoutubePaging.collect(page(0, next = "t0"), { it }, { page(1, next = "t${++n}") })
            null
        } catch (e: YoutubeFailure) {
            e
        }
        assertEquals("unavailable", failure?.code)
        assertTrue(n <= YoutubePaging.MAX_PAGES)
    }

    @Test
    fun tooManyItemsIsAFailure() {
        val big = PageResult((0 until YoutubePaging.MAX_ITEMS).toList(), "b")
        try {
            YoutubePaging.collect(big, { it }, { page(1) })
            fail("expected a failure")
        } catch (e: YoutubeFailure) {
            assertEquals("unavailable", e.code)
        }
    }

    @Test
    fun aFetchFailurePropagates() {
        try {
            YoutubePaging.collect(page(1, next = "b"), { it }, { throw java.io.IOException("down") })
            fail("expected an exception")
        } catch (e: java.io.IOException) {
            assertEquals("network", YoutubeFailure.from(e).code)
        }
    }
}
