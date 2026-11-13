package x

import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id

@Entity
data class Product( // HIT REP-35
    @Id
    val id: Long,
    @Enumerated // HIT REP-16
    val kind: ProductKind,
    @Enumerated(EnumType.STRING)
    val status: ProductStatus,
)
