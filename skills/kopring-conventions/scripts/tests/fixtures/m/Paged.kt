package x

import org.springframework.data.domain.PageImpl

class Paged {
    fun page() = PageImpl(listOf(1))
}
