package meditofoundation.medito.youtube

/** One page of a list and the token for the next, or null at the end. */
class PageResult<Item, Token : Any>(val items: List<Item>, val next: Token?)

object YoutubePaging {
    const val MAX_PAGES = 400
    const val MAX_ITEMS = 10_000

    /**
     * Follows [first] to the last page and returns every item in order. A
     * token that comes back twice, or a list past the limits, is a failure:
     * returning a part of a playlist as if it were the whole would be worse
     * than saying so. [keyOf] must make equal tokens equal keys.
     */
    fun <Item, Token : Any> collect(
        first: PageResult<Item, Token>,
        keyOf: (Token) -> Any,
        fetch: (Token) -> PageResult<Item, Token>,
    ): List<Item> {
        val items = ArrayList<Item>(first.items)
        val seen = HashSet<Any>()
        var next = first.next
        var pages = 1
        while (next != null) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            if (!seen.add(keyOf(next)) || ++pages > MAX_PAGES) throw YoutubeFailure.tooLarge()
            val page = fetch(next)
            items.addAll(page.items)
            if (items.size > MAX_ITEMS) throw YoutubeFailure.tooLarge()
            next = page.next
        }
        return items
    }
}
