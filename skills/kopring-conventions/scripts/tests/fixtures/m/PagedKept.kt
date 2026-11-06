package x

import org.springframework.data.domain.PageImpl

class PagedKept {
    fun page() = PageImpl(listOf(1)) // HIT REP-10
}
