package x

import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional
class PaymentService(
    private val paymentClient: PaymentClient, // HIT TX-2
    private val paymentRepository: PaymentRepository,
)
