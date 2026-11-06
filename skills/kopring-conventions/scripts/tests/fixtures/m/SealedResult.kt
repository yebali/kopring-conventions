package x

sealed interface PaymentResult

data class Approved(
    val id: Long,
) : PaymentResult

data class Declined(val reason: String) : PaymentResult

data object Pending : PaymentResult
