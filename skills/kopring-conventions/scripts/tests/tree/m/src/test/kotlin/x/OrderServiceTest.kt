package x

import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.nio.file.Files

class OrderServiceTest {
    @Nested
    inner class `order creation` {
        @Test
        fun `rejects an order without items`() = Unit

        @Test
        fun `주문 항목이 없으면 거부된다`() = Unit // HIT TST-6

        @Test
        fun rejectsEmptyOrder() = Unit // HIT TST-6
    }

    @Nested
    inner class `주문 취소` { // HIT TST-5
        @Test
        fun `creates a temporary file`() {
            Files.createTempDirectory("orders") // HIT TST-31
            Files.createTempDirectory(tempDir, "orders")
        }
    }

    fun buildOrder() = Unit
}
