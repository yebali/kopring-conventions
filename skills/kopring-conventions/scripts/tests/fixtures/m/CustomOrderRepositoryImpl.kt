package x

class CustomOrderRepositoryImpl {
    fun inRange(from: Long, to: Long) = order.orderedAt.between(from, to) // HIT REP-40

    fun priced(min: Long, max: Long) = order.price.between(min, max)

    fun window(from: Long, to: Long) = order.orderedAt.goe(from).and(order.orderedAt.lt(to))
}
