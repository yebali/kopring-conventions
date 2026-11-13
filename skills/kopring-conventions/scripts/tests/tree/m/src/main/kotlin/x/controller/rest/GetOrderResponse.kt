package x.controller.rest

import x.entity.Order // HIT CTL-6
import x.service.command.GetOrderResult

data class GetOrderResponse(val id: Long)
