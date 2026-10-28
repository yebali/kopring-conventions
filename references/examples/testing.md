# Testing — Worked Examples

Rule text lives in [testing.md](../testing.md) (`TST-*`) and [test-coverage.md](../test-coverage.md) (`COV-*`); each heading names the rule its example illustrates.

## TST-2 — SpringBootTestSupport and Testcontainers

Each module keeps its own `TestcontainersConfiguration` and starts its own containers: PostgreSQL, plus Redis if the module uses it. The wiring rests on three mechanisms:

- **Redis needs `name = "redis"`.** Spring Boot's `RedisContainerConnectionDetailsFactory` does not type-match a plain `GenericContainer`; it matches the `"redis"` connection-name hint, so the bean carries `@ServiceConnection(name = "redis")`. `PostgreSQLContainer` is matched by type and needs no hint. In Testcontainers 2.x `PostgreSQLContainer` is non-generic: declare `PostgreSQLContainer`, not `PostgreSQLContainer<*>`.
- **A database bootstrap runs in the `@Bean`, after `start()`.** A module that needs a raw-JDBC bootstrap before Hibernate `create-drop` (a `CREATE EXTENSION`, named enum types) runs it inside the postgres `@Bean` body right after `start()`, which precedes the `DataSource` and `EntityManagerFactory` beans. `withInitScript` is not used.
- **`application-test.yml` keeps literal `spring.data.redis.host` and `port`** when the base `application.yml` declares the port as a placeholder without a default (`${REDIS_PORT}`): `RedisProperties.port` is a primitive `Int`, so the placeholder must resolve at bind time even though `@ServiceConnection` supplies the live connection. The test yml keeps `host: localhost` / `port: 6379` as bind-time values; the connection details win at runtime.

```kotlin
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfiguration {
    @Bean
    @ServiceConnection
    fun postgresContainer(): PostgreSQLContainer =          // 2.x: non-generic, no <*>
        PostgreSQLContainer(DockerImageName.parse(POSTGRES_IMAGE)).apply {
            withDatabaseName("testdb"); withUsername("test"); withPassword("test")
            start()
            initializeDatabase(this)                         // raw-JDBC bootstrap — before create-drop
        }

    @Bean
    @ServiceConnection(name = "redis")                       // GenericContainer is NOT type-matched
    fun redisContainer(): GenericContainer<*> =
        GenericContainer<Nothing>(REDIS_IMAGE).apply { withExposedPorts(6379) }

    companion object { /* image constants + private bootstrap fns */ }
}

// SpringBootTestSupport pulls it in — no ApplicationContextInitializer / TestPropertyValues:
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
abstract class SpringBootTestSupport { ... }
```

## TST-3 — Inherited dependencies

```kotlin
// ✅ Good — use inherited dependencies as-is
class OrderServiceTest : SpringBootTestSupport() {
    @Test
    fun `주문을 취소한다`() {
        applicationEventPublisher.publishEvent(event)   // inherited
        orderService.cancel(command)                     // inherited
    }
}

// ❌ Bad — re-declaring dependencies the support class already declares
class OrderServiceTest : SpringBootTestSupport() {
    @Autowired lateinit var applicationEventPublisher: ApplicationEventPublisher
    @MockkBean lateinit var paymentClient: PaymentClient
}
```

## TST-5 · TST-6 — Nested grouping and Korean names

```kotlin
// ✅ Good — @Nested per domain feature, Korean backtick names, no @DisplayName
class OrderServiceTest : SpringBootTestSupport() {
    @Nested
    inner class `주문 생성` {
        @Test fun `생성에 성공한다`() { ... }
        @Test fun `재고가 부족하면 주문할 수 없다`() { ... }
    }

    @Nested
    inner class `주문 취소` {
        @Test fun `주문을 취소하면 상태가 CANCELED 가 된다`() { ... }
    }

    @Nested
    inner class `주문 조회` {
        @Test fun `주문을 반환한다`() { ... }
    }
}

// ❌ Bad — no grouping, English PascalCase group, @DisplayName
class OrderServiceTest : SpringBootTestSupport() {
    @Nested
    inner class Create { ... }

    @DisplayName("Create Order")
    @Test
    fun `주문을 생성한다`() { ... }
}
```

## TST-8 — Transactional placement

```kotlin
// ✅ Repository test — class-level @Transactional (bulk DML needs a transaction boundary)
@Transactional
class CustomOrderRepositoryImplTest : SpringBootTestSupport() {
    @Test
    fun `memberId 에 속한 모든 주문을 삭제한다`() {
        orderRepository.deleteAllByMemberId(member.id)
    }
}

// ✅ Service test — no @Transactional and no teardown deletes: rows stay, assertions scope
//    to this test's own ids (TST-11). A rolled-back Repository test needs no cleanup at all.
class OrderServiceTest : SpringBootTestSupport() {
    @Test
    fun `주문을 생성한다`() {
        val result = orderService.create(command)
    }
}
```

## TST-9 — Repository query and ordering

```kotlin
// save data → query with Sort/PageRequest → assert ordering
val member = saveMember()
saveOrder(member = member, totalPrice = 9_500L)
saveOrder(member = member, totalPrice = 7_500L)
val results = orderRepository.pageByQuery(OrderQuery(memberId = member.id, pageable = PageRequest.of(0, 10, Sort.by("totalPrice").descending())))
assertThat(results.content.map { it.totalPrice }).containsExactly(9_500L, 7_500L)
```

## TST-10 — Plain unit test

```kotlin
// plain class (no SpringBootTestSupport), @Nested, classpath resource loading
class OrderCsvParserTest {
    private fun classpathFile(name: String): Path =
        Path.of(requireNotNull(javaClass.classLoader.getResource("csv/$name")) { "Test resource not found: csv/$name" }.toURI())

    @Nested
    inner class `주문 CSV 파싱` {
        @Test
        fun `헤더를 제외한 모든 행을 주문으로 변환한다`() {
            assertThat(OrderCsvParser().parse(classpathFile("orders.csv"))).hasSize(3)
        }
    }
}
```

## TST-13 — Fixtures in local scope

```kotlin
// ✅ Good — faker helper + local variables
class MemberServiceTest : SpringBootTestSupport() {
    @Test
    fun `가입에 성공한다`() {
        val email = randomEmail()
        val member = saveMember(email = email)
        assertThat(member.email).isEqualTo(email)
    }

    private fun saveMember(email: String = randomEmail()): Member = memberService.register(command)  // helper calls service
}

// ❌ Bad — literal identities + class-level properties
class MemberServiceTest : SpringBootTestSupport() {
    private val testEmail = "test@example.com"
    private val testMember by lazy { saveMember() }
    @Test fun `가입한다`() { val member = Member(email = "x@y.com") }
}
```

## TST-19 — Controller test with scoped assertions

`buildAuth(memberId)` is the support's `RequestPostProcessor` that attaches the authenticated principal (an auth header, or Spring Security's `user(...)`).

```kotlin
class OrderControllerTest : SpringBootTestSupport() {
    @Nested
    inner class `주문 생성` {
        @Test
        fun `POST api_v1_orders 는 201 을 반환한다`() {
            val member = saveMember()
            mockMvc.perform(post("/api/v1/orders").with(buildAuth(member.id))
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(CreateOrderRequest(memberId = member.id))))
                .andExpect(status().isCreated)
                .andExpect(jsonPath("$.status").value(OrderStatus.PENDING.name))
        }
    }

    @Nested
    inner class `주문 단건 조회` {
        @Test
        fun `GET api_v1_orders_orderId 는 주문을 반환한다`() {
            val member = saveMember()
            val order = saveOrder(member = member)
            mockMvc.perform(get("/api/v1/orders/${order.id}").with(buildAuth(member.id)))
                .andExpect(status().isOk)
                .andExpect(jsonPath("$.id").value(order.id.toString()))
        }
    }

    @Nested
    inner class `주문 목록 조회` {
        @Test
        fun `GET api_v1_orders 는 이 회원의 주문 목록을 반환한다`() {
            val member = saveMember()
            saveOrder(member = member)
            saveOrder(member = member)

            // ✅ the endpoint's own memberId filter makes the exact count true regardless of other tests
            mockMvc.perform(get("/api/v1/orders").param("memberId", member.id.toString()).with(buildAuth(member.id)))
                .andExpect(status().isOk)
                .andExpect(jsonPath("$.totalElements").value(2))
            // ❌ without .param(...) this needs an empty DB, i.e. a teardown that deletes everyone's rows
        }
    }
}
```

## TST-22 — Exception and ErrorCode assertions

```kotlin
// Controller test — status + ErrorCode in $.type
mockMvc.perform(get("/api/v1/orders/$nonExistentId").with(buildAuth(memberId)))
    .andExpect(status().isNotFound)
    .andExpect(jsonPath("$.type").value("ORDER-1000"))

// Service test — the exception type is the assertion
assertThatThrownBy { orderService.get(UUID.randomUUID()) }
    .isInstanceOf(OrderNotFoundException::class.java)

// Service test — one exception type carries several codes, so the ErrorCode is checked too
assertThatThrownBy { orderService.create(command) }
    .isInstanceOf(OrderInvalidValueException::class.java)
    .extracting("errorCode").isEqualTo(ErrorCode.ORDER_ITEM_QUANTITY_INVALID)

// ❌ asserting the message
assertThatThrownBy { orderService.create(command) }.hasMessage("Order item quantity is invalid")
```

## COV-4 — Private method via public input

```kotlin
// ✅ Good — reach a private branch via a combination of public inputs (this one test covers the deny branch of the private check)
val order = saveOrder()
orderService.ship(ShipOrderCommand(orderId = order.id))
assertThatThrownBy { orderService.cancel(CancelOrderCommand(orderId = order.id)) }
    .isInstanceOf(OrderNotCancelableException::class.java)

// ❌ Bad — calling private directly via reflection / bypassing by relaxing visibility (both prohibited)
OrderService::class.declaredMembers.first { it.name == "checkCancelable" }.call(...)
internal fun checkCancelable(...) { ... }   // do not change production visibility for the sake of tests
```
