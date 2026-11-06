package x

import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.IdClass
import java.io.Serializable

@Entity
@IdClass(OrderLineId::class)
class OrderLine(
    @Id
    val orderId: Long,
    @Id
    val lineNo: Int,
)

data class OrderLineId(
    val orderId: Long = 0,
    val lineNo: Int = 0,
) : Serializable
