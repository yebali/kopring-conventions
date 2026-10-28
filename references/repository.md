# Repository Conventions

**Owns:** Repository interfaces, QueryDSL construction, entity mapping, persistence rules, and Flyway migration rules. **Read when:** editing a Repository, Entity, persistence query, or migration.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| REP-1 | | No `@Query` or `@Modifying` on any repository method | [§2](#2-query-construction) |
| REP-2 | | Derived query for a single field, QueryDSL `Custom*Repository` for everything else, `@EntityGraph` only for the listed exceptions | [§2.1](#21-priority) |
| REP-3 | | No stereotype annotation on `Custom*RepositoryImpl` | [§2](#2-query-construction) |
| REP-4 | | No `@Transactional` on `Custom*RepositoryImpl`; with two collection fetch joins declare one side a `Set` | [§2](#2-query-construction) |
| REP-5 | | Extract the `by()` predicate and call it inline; never extract the select–join–where–fetch skeleton | [§2.2](#22-by-predicate) |
| REP-6 | | Use the Q-class default singleton; a self-join alias has a meaningful name | [§2.3](#23-q-class-import) |
| REP-7 | | No QueryDSL projection unless explicitly asked; load the full entity | [§2](#2-query-construction) |
| REP-8 | | Repository names: `findBy`/`existsBy`/`countBy`/`deleteBy`, `listByQuery`, `pageByQuery`, `existsByQuery`, `countGroupedBy{Axis}`; never `get*` | [§3](#3-naming-and-query-objects) |
| REP-9 | | Two or more combined or optional conditions go into one Query object; `list`/`page`/`exists`/`count` stay separate methods | [§3.1](#31-multi-condition-reads) |
| REP-10 | | A paged read uses `PageableExecutionUtils.getPage` and `Page.empty`, never `PageImpl` | [§3.1](#31-multi-condition-reads) |
| REP-11 | | A null filter means no condition; an empty list matches no rows | [§4](#4-filters-and-ordering) |
| REP-12 | | Every ordering ends with the entity id as a tie-breaker | [§4](#4-filters-and-ordering) |
| REP-13 | | Native SQL binds every value as a parameter and reads rows through `Tuple` aliases | [§5](#5-native-sql) |
| REP-14 | | `@Column` only for what Hibernate cannot infer (listed exceptions) | [§6](#6-entity-mapping) |
| REP-15 | | A reference to another entity — in another domain or the same one — is a `@ManyToOne`, never a raw id field | [§6](#6-entity-mapping) |
| REP-16 | | Enum columns are `@Enumerated(EnumType.STRING)` | [§6](#6-entity-mapping) |
| REP-17 | | A JPA entity's state fields have a `protected set`; state changes through named transition methods (a `@RedisHash` entity: §10) | [§6](#6-entity-mapping) |
| REP-18 | | Transition methods are short verbs without the cause or the target state | [§6](#6-entity-mapping) |
| REP-19 | | `Persistable` only on entities saved in bulk with application-assigned ids | [§6](#6-entity-mapping) |
| REP-20 | | Escape PostgreSQL keywords in `@Table`; no reserved words as property names | [§6](#6-entity-mapping) |
| REP-21 | | Entities carry no Spring dependency; a delegated computed property needs its relation loaded | [§6](#6-entity-mapping) |
| REP-22 | ⚠ | *If the project uses PostgreSQL JSONB:* a JSONB column carries both `@JdbcTypeCode(SqlTypes.JSON)` and `@Column(columnDefinition = "jsonb")` | [§7](#7-jsonb) |
| REP-23 | | *JSONB:* JSONB queries go through one shared JSONB query util; JSONB values compare and sort as text | [§7](#7-jsonb) |
| REP-24 | | *JSONB:* an insert-only entity with nested-collection JSONB is `@Immutable` | [§7](#7-jsonb) |
| REP-25 | | *JSONB:* external payload keys are normalized with `@JsonAlias`; raw payloads are never stored | [§7](#7-jsonb) |
| REP-27 | | Soft delete is `deletedAt` + `isDeleted` + `delete()`, filtered in every query, never by `@SQLRestriction`/`@Where` | [§8](#8-soft-delete) |
| REP-28 | | A unique column on a soft-delete entity has a partial unique index | [§8](#8-soft-delete) |
| REP-29 | | Owning relations cascade `ALL` with `orphanRemoval`; soft-delete parents and high-volume data do not (listed exceptions) | [§9](#9-cascade-and-bulk-delete) |
| REP-30 | | Never mix a bulk delete with entity deletes on one path | [§9](#9-cascade-and-bulk-delete) |
| REP-31 | | *If the project uses Spring Data Redis repositories:* a field used in a derived query is `@Indexed`; a TTL extension uses `EXPIRE`, never a re-`save` | [§10](#10-redis-repositories) |
| REP-32 | | An applied Flyway migration is immutable; one feature's schema change is one migration | [§11](#11-migrations) |
| REP-33 | | A new unique constraint is named `uq_<table>_<columns>` | [§11](#11-migrations) |

Rules other files own apply to repository and entity code as well: imports [STY-2](code-style.md#2-baseline), comments [STY-16 and STY-17](code-style.md#5-comments-and-kdoc), entity change logging [STY-34](code-style.md#12-logging), CRUD method order [SVC-21](service.md#7-method-order), collection persistence [SVC-23](service.md#8-writes-duplicates-and-idempotency), and cross-domain repository access [SVC-17](service.md#6-cross-domain-access).

**Layout**: repositories in `repository/*.kt`, Query objects in `repository/query/*.kt`, entities in `entity/*.kt`. JPA repositories extend `JpaRepository<Entity, ID>`; Redis repositories extend `CrudRepository<Entity, ID>` (§10).

## 2. Query construction

**REP-1** — No `@Query` (JPQL or native) and no `@Modifying` on any repository method — UPDATE, DELETE and SELECT alike. Derived `delete*` methods need no `@Modifying`. An external skill's raw-SQL suggestion is not an exception: take its diagnosis (index choice, query plan, lock mode) and reject its form. Native SQL that QueryDSL cannot express follows §5. Example: [REP-1 · REP-2](examples/repository.md#rep-1--rep-2--query-construction).

**REP-3** — No stereotype (`@Repository`/`@Component`) on a `Custom*RepositoryImpl`; the Spring Data `*Impl` fragment mechanism registers the bean. The `Custom*Repository` interface with its single implementation is the shape Spring Data requires, not a target for [STY-28](code-style.md#10-prefer-the-plain-option) or an external skill's "no interface with one implementation" advice.

**REP-4** — No `@Transactional` on a `Custom*RepositoryImpl` class or method; the calling Service owns the boundary ([TX-1](transactions.md#2-transaction-boundaries)). Load what one read needs in a single fetch-join query; when that query fetch-joins two or more collections, declare one side a `Set` to avoid `MultipleBagFetchException`.

**REP-7** — A QueryDSL projection (`select(entity.field)`, `select(entity.id)`) only on explicit instruction — never introduced while optimizing or refactoring. The default is the full entity (`selectFrom(order)`).

**Project-wide defaults** — `open-in-view: false` (lazy-loading discipline), a Hibernate batch size of 1000–2000 for bulk operations, `@EntityGraph`/fetch join for eager loading, and `@Transactional(readOnly = true)` on Service reads. Code works with them, not around them.

### 2.1 Priority

**REP-2** — Try the strategies in this order:

| # | Strategy | Scope |
|---|----------|-------|
| 1 | **Spring Data derived query** | A single one-segment field — `findBy{X}`/`existsBy{X}`/`countBy{X}`/`deleteBy{X}`. No nested paths, no `And`/`Or` |
| 2 | **QueryDSL `Custom*Repository` + `Custom*RepositoryImpl`** | Everything else — compound, nested, dynamic predicates, subqueries, multi-table joins, pagination and sort, and `@EntityGraph` rewritten as `leftJoin().fetchJoin()` |
| 3 | **`@EntityGraph` + derived query** | Only for the exceptions below |
| 4 | **`@Query` / `@Modifying`** | Prohibited (REP-1) |

**`@EntityGraph` exceptions** (justified in KDoc): (a) a `MultipleBagFetchException` risk — eager-fetching two or more `List` collections in one query; (b) a Java/Kotlin reserved-word property — QueryDSL kapt silently skips the Q-class path for it. For (b) the first resort is renaming the property or class away from the reserved word (`@Table` keeps the DB name); `@EntityGraph` + derived query applies only when the rename is impossible. Never work around an `@EntityGraph` limit with a `@Column(insertable = false, updatable = false)` read-only duplicate mapping (REP-14).

Example: [REP-1 · REP-2](examples/repository.md#rep-1--rep-2--query-construction).

### 2.2 by() predicate

**REP-5** — Extract the conditions into `private fun by(query): BooleanBuilder`, reused by the content query and the count query, and call it inline as `.where(by(query))` at every use site. Do not hoist it to `val where = by(query)` ([STY-19](code-style.md#6-single-use-intermediates); `by()` is a cheap builder, harmless to call twice), and never assemble a `BooleanBuilder` imperatively inside `pageByQuery()`. The skeleton half of REP-5 is §2.4.

Example: [REP-5](examples/repository.md#rep-5--by-predicate-extraction).

### 2.3 Q-class import

**REP-6** — Import the kapt-generated singleton; no local alias fields (`private val order_ = QOrder("order_")`).

- **Self-join** — the same table twice needs a second alias: name it by meaning (`parentCategory`, `ancestorCategory`), never with a formal suffix (`category_`).
- **Reserved-word entity name** — QueryDSL generates the singleton as `keyword$`; hide the `$` with a Kotlin rename import, not an alias field.

Example: [REP-6](examples/repository.md#rep-6--q-class-import-and-self-join-alias).

### 2.4 Query skeleton stays inline

Write the full `selectFrom…join…where…fetch` chain inside each method so it maps 1:1 to the executed SQL (REP-5). Skeletons are not shared across repositories or strategies (service-layer QueryDSL strategies included) — query-skeleton duplication is not a [STY-15](code-style.md#4-files-and-packages) target.

| Allowed (reads inline inside the chain) | Forbidden (hides the query shape from the call site) |
|---|---|
| A `by()` predicate reused by the content and count queries | The whole select–join–where–fetch skeleton in a separate method |
| A chainable extension such as `withPagination()` or `jsonbField()` | The pagination tail (`.withPagination().fetch()` + `PageableExecutionUtils.getPage`) in a `pageOf()`-style helper |
| Conditions encapsulated in a Query object (`Page*Query`, `Exists*Query`) | A shared skeleton in an interface default method such as `executeMatchingQuery()` |

A line comment inside the chain sits only on a `join`/`where`/`orderBy` step whose reason the operator does not show (`.where(category.path.like("$prefix/%")) // 하위 트리 전체`), never on `.fetch()` or a self-explanatory step.

Example: [REP-5](examples/repository.md#rep-5--query-skeleton-stays-inline).

## 3. Naming and query objects

**REP-8** — Repository methods use these names:

| Type | Method prefix | Return | Query class |
|------|---------------|--------|-------------|
| Single | `findBy*` / `existsBy*` / `countBy*` / `deleteBy*` | `Entity?` / `Boolean` / `Long` | not needed |
| Multiple | derived `findAllBy*` (single key) or Custom `listByQuery(query)` (multiple conditions) | `List<Entity>` | `List*Query` (multiple conditions) |
| Paginated | `pageByQuery(query)` | `Page<Entity>` | `Page*Query` required |
| Existence (condition-branching) | `existsByQuery(query)` | `Boolean` | `Exists*Query` |
| Count (condition-branching) | `countByQuery(query)` | `Long` | `Count*Query` |
| Count (GROUP BY distribution) | `countGroupedBy{Axis}(query)` | `Map<Enum, Long>` | `Count*Query` (one method per axis, Query shared) |

`get*` is a Service prefix; repositories use `find*` for single, `list*`/`findAllBy*` for multiple, `page*` for paged.

- **Standard names are `listByQuery`/`pageByQuery`** — entity-baked variants (`pageOrders`, `findPageBy`) are prohibited. A descriptive name is allowed only when one entity needs more than one distinct paged projection (e.g. `pageWithItemSummary` beside `pageByQuery` on `Order`); the entity's main filtered page is always `pageByQuery`.
- **GROUP BY distribution count** — `countBy*` is a derived-query prefix and reads as "filtered count", so the grouping axis is named `countGroupedBy{Axis}(query): Map<Enum, Long>` (`countGroupedByStatus`). The filter axis is carried by the `Count*Query` type, not the name; two axes get two methods sharing the Query. A family that returns a projection list (e.g. counts grouped by product and status together) is not `Map<Enum, Long>` and is outside this naming rule.

### 3.1 Multi-condition reads

**REP-9** — A read with two or more combined conditions, or nullable optional filters, does not spawn one derived method per combination (`existsByProductIdAndOrderDeletedAtIsNullAndOrderPaidAtIsNotNull` and its forks). Its conditions go into a Query object behind a single `*ByQuery` method, and the call site states intent through named arguments. A single-field condition (`findById`) stays derived; `@Query` JPQL is never the way around it (REP-1).

- **`list`/`page`/`exists`/`count` are always separate methods** — a different return shape is never folded into one method. Only methods on the same filter axis share a `by(query)`: `listByQuery(ListOrderQuery)` and `existsByQuery(ListOrderQuery)` share one filter and one `by()`, while `pageByQuery(PageOrderQuery)` has its own axis (period, explicit id list) and its own `by()`.

**Non-PK list-read clustering** — the trigger is not limited to filters on the entity's own primary key. When one entity has two or more `List<Entity>` reads filtered by non-own-PK conditions (a foreign key such as `memberId`/`orderId`, a status or type column) that are variations of each other — overlapping condition axes (`findAllByMemberIdWithItems` + `findAllByMemberIdsAndStatus`), or a with/without-fetch or extra-filter pair — collapse them into one `listByQuery(List*Query)` whose nullable fields are the union of the filters, with the superset fetch graph.

- **Own-PK reads stay** — `findById`, fetch-graph variants `findByIdWith*`, and multi-PK `listByIds(ids…)`/`listByIdsWith*` are keyed on the entity's own id.
- **An isolated single non-PK read stays derived** — one lone `findAllBy<fk>` on an entity (`OrderItemRepository.findAllByOrder`) is not method explosion. The rule fires only at two or more variation reads.
- **Mechanically distinct reads stay separate** — reads that cannot share one query skeleton are not a variation cluster. For a path-addressed tree entity: the paged listing of one level of children (prefix `LIKE` + `notLike` `%/%`) or of a name match over the subtree, the unpaged whole subtree (`findAllDescendants`, prefix `LIKE`), a multi-prefix age sweep (OR of path prefixes + `createdAt <`), exact `IN` (`findAllByPathIn`), or a different traversal.
- **A single-condition single-vs-`In` pair** (`findAllByXId` + `findAllByXIdIn`, same axis) needs no Query object — keep the `In` form and drop the single variant (callers pass `listOf(id)`).

**REP-10** — A paged read builds its page with `PageableExecutionUtils.getPage(content, pageable) { countQuery }`, which skips the count query on a partial last page, never with `PageImpl(content, pageable, count)`. An empty short-circuit returns `Page.empty(pageable)`, never `PageImpl(emptyList(), pageable, 0L)`.

Example: [REP-9](examples/repository.md#rep-9--query-object-clustering).

## 4. Filters and ordering

**REP-11** — In a Query object a `null` filter adds no condition, and an empty list matches no rows:

```kotlin
.and(query.ids?.let { if (it.isEmpty()) Expressions.FALSE.isTrue else order.id.`in`(it) })
```

Never `takeIf { it.isNotEmpty() }` to mean "all": it turns an empty selection into every row.

**REP-12** — Every ordering ends with the entity id ascending as a tie-breaker, so offset paging never skips or repeats rows (`orderTransformer` is the project's `Sort` → `OrderSpecifier` converter):

```kotlin
.orderBy(*orderTransformer.transform(sort), order.id.asc())
.withPagination(query.pageable, *orderTransformer.transform(query.pageable.sort), order.id.asc())   // paged form
```

## 5. Native SQL

**REP-13** — Native SQL binds every value with `setParameter`; only fixed fragments chosen in code may be concatenated into the SQL string. Rows are read through `createNativeQuery(sql, Tuple::class.java)` and column aliases, never through positional `Array<*>` casts.

```kotlin
// ✅ bound value, row read by alias
entityManager.createNativeQuery("SELECT p.id AS id, p.stock AS stock FROM product p WHERE p.sku LIKE :prefix", Tuple::class.java)
    .setParameter("prefix", "$prefix%")
    .resultList.map { (it as Tuple).get("stock", Long::class.javaObjectType) }

// ❌ value concatenated into the SQL, row read by position
entityManager.createNativeQuery("SELECT p.id, p.stock FROM product p WHERE p.sku LIKE '$prefix%'")
    .resultList.map { (it as Array<*>)[1] as Long }
```

## 6. Entity mapping

**REP-14** — `@Column` is for what Hibernate cannot infer — nothing else.

| Option | Use | Reason |
|--------|-----|--------|
| `name` | ❌ | `PhysicalNamingStrategy` maps camelCase to snake_case (`shippedAt` → `shipped_at`) |
| `nullable` | ❌ | NOT NULL is owned by the Flyway migration, and `ddl-auto=validate` does not check nullability — the annotation only shapes `ddl-auto: update` local DDL while duplicating what the Kotlin type already states |
| `insertable` / `updatable` | ❌ | One column is never mapped twice. A reference is a `@ManyToOne` read through `foo?.id` (REP-15); Kotlin `val` gives code-level read-only |
| `columnDefinition` | ✅ | PostgreSQL types Hibernate cannot infer: `jsonb`, `text` |
| `length` | ✅ | Only when ≠ the default 255 |
| `unique` | ✅ | Single-column UNIQUE (compound → `@Table(uniqueConstraints = …)`) |

Accepted exceptions:

- **Creation-timestamp columns** may carry `@Column(updatable = false)` for `AuditingEntityListener` cooperation (`BaseTimeEntity.createdAt`, with `@EntityListeners(AuditingEntityListener::class)` + `@CreatedDate`). `lastModifiedAt` stays unannotated.
- **A DB-generated column** is mapped `insertable = false, updatable = false`.
- **A `@MapsId` derived identifier** has no `@Column(name = …)` on the `@Id` field — with `@MapsId` the id column is the association's `@JoinColumn`.
- **`@IdClass` key fields** each carry `@Column(name = …)` when the project configures `ImplicitNamingStrategyComponentPathImpl`: it treats the id class as a component and would name the columns `id_<field>`.

Example: [REP-14](examples/repository.md#rep-14--entity-column-policy).

**REP-15** — A reference to another entity is a `@ManyToOne` (`@ManyToOne val foo: Foo?`, read through `bar.foo?.id`), never a separate `fooId: UUID` field — whether the target is in another domain or the same one (`OrderItem.order`, not `orderId: UUID`). An id of a row another service owns (a member id when members live in another service) has no entity in this service and stays a `UUID`. [SVC-17](service.md#6-cross-domain-access) does not apply to entity imports — an entity may import other entities.

**REP-16** — An enum column is `@Enumerated(EnumType.STRING)`.

**REP-17** — A JPA entity's state fields are `var … protected set` and change only through named transition methods; no caller assigns them directly. A `@RedisHash` entity keeps its state in constructor `var`s instead ([REP-31](#10-redis-repositories)); its changes still go through named methods.

**REP-18** — Transition methods are short verbs — `Order.hold()`/`complete()`/`cancel()`, `Payment.approve()`/`fail()`/`refund()`. The cause stays out of the name (`failByTimeout` — the cause belongs in the caller's log), and so does the target state (`resetToPending`). Qualify a name only to tell siblings apart, and give a variant that also changes side state (a counter) its own method (`reset` vs `reassign`). DTO names follow [STY-50](code-style.md#16-filler-suffixes-and-dto-casing); this is the entity counterpart.

**REP-19** — `Persistable<UUID>`, with a `@Transient` new flag cleared in `@PostPersist`/`@PostLoad`, only on entities saved in bulk with application-assigned ids. Without it, `save` treats an entity whose id is already set as existing and merges it with a SELECT before the INSERT; that cost matters only for bulk saves, so no other entity implements it.

**REP-20** — Escape PostgreSQL keywords in `@Table(name = "\"order\"")`, and keep reserved words out of property names (`sequence`, not `order`) — a reserved word also breaks QueryDSL kapt (§2.1 exception (b)).

**REP-21** — `@Entity` + `@Table`; computed values in `get()` backing-property style; `@EntityListeners` for lifecycle hooks; no Spring dependency in `entity/`. A related entity's value is delegated through a computed property instead of a duplicated column (`OrderItem.productName get() = product.name`); the related entity must be loaded (`@EntityGraph`/`fetchJoin()`) before the property is read outside a transaction, or `LazyInitializationException` fires.

Example: [REP-21](examples/repository.md#rep-21--entity-layer-and-computed-property).

## 7. JSONB

*If the project uses PostgreSQL JSONB.*

**REP-22** — A JSONB column carries both `@JdbcTypeCode(SqlTypes.JSON)` and `@Column(columnDefinition = "jsonb")`. Missing either breaks Hibernate's JSONB serialization — silent on read, cryptic errors on write.

**REP-23** — JSONB queries go through one shared JSONB query util: a `.jsonbField(vararg keys)` extension extracts the value as text, then `.containsIgnoreCase()`, `.eq(...)`. There is no numeric cast — a JSONB value compares and sorts as text. Sorting passes the `Sort` to the shared `Sort` → `OrderSpecifier` transformer (`OrderSpecifierTransformer(entityPath).transform(sort)`); a property whose first segment is a JSONB map field (`metadata.priority`) orders by that key's text value, so numbers sort lexicographically (`"10"` before `"9"`). There is no per-field cast or field allow-list.

**REP-24** — An insert-only entity carrying a JSONB value with a nested collection (`snapshot = {"items": [{"sku": "A-1", "quantity": 2}]}`) is `@org.hibernate.annotations.Immutable`. Hibernate's JSON type does not deep-copy the snapshot, so such a value is judged dirty on every flush and each inserted row gets a redundant UPDATE; flat maps do not reproduce it.

- **Target**: an entity with no update path (all-`val` constructor; the repository only `saveAll`, reads and deletes) carrying such a field.
- **Apply even when callers pass an empty value** — the criterion is the entity's declared shape (insert-only + JSONB), not the values callers pass.
- ❌ Never on an updatable entity — `@Immutable` silently ignores dirty-checked UPDATEs, and Hibernate rejects a bulk UPDATE on it (a bulk DELETE is allowed). Check `var` fields and repository call sites first.

**REP-25** — External payload keys are normalized with Jackson `@JsonAlias` on the typed payload class's properties (`PaymentApproval.approvalNumber` aliases `approvalNo`). A mapper converts the raw payload into the typed class, which serializes it into the JSONB column (`payment.approval`). The raw external payload is never stored verbatim.

Example: [REP-22 · REP-23 · REP-24](examples/repository.md#rep-22--rep-23--rep-24--jsonb).

## 8. Soft delete

**REP-27** — An entity that keeps a deletion trail has a nullable `deletedAt` instead of a physical delete, in three fixed pieces: the `deletedAt` column (`protected set`), an `isDeleted` getter, and a `delete()` transition method that logs only the field it assigns ([STY-34](code-style.md#12-logging)). Filtering is always stated in the query — never `@SQLRestriction`, `@SQLDelete` or `@Where`. Single and list reads `and` `deletedAt.isNull` in the where clause; paged reads seed the `by()` builder with it.

**REP-28** — A unique column on a soft-delete entity has a partial unique index (`WHERE deleted_at IS NULL`); a plain UNIQUE lets a deleted row occupy the value forever and blocks re-registration with the same code.

- **Partial indexes exist only where Flyway runs.** JPA `@Table`/`@Column` cannot express a `WHERE` clause, so a profile on `ddl-auto: create-drop` (tests) or `update` (local) has no unique constraint on such a column — duplicate codes are accepted there. Tests account for this.
- **Accepted non-partial exceptions**: a value that must stay occupied after soft delete (an email that can never be re-registered, an ordinal a deleted row keeps) uses a plain UNIQUE on purpose.

Example: [REP-27 · REP-28](examples/repository.md#rep-27--rep-28--soft-delete-shape).

## 9. Cascade and bulk delete

**REP-29** — Owning relationships declare `cascade = [CascadeType.ALL], orphanRemoval = true`, backed by DB `ON DELETE CASCADE` (defense in depth).

- **Soft-delete entities** (REP-27) cascade nothing; the Service handles deletion explicitly. Accepted exception: a collection that is the soft-delete parent's live child set, replaced as a whole on every edit (`Order.items` on every order edit), keeps `cascade = ALL, orphanRemoval = true` — the parent row is only soft-deleted, so the cascade never removes it.
- **High-volume accumulating data** (event logs, per-order tracking records) has no `@OneToMany` on its parent — loading it would risk OOM.

**REP-30** — A JPQL bulk delete (QueryDSL `queryFactory.delete`) is never mixed with entity deletes on one path (`TransientObjectException`, session inconsistency): a path deletes entities throughout, or runs bulk deletes only.

Example: [REP-30](examples/repository.md#rep-30--bulk-delete-mixing).

## 10. Redis repositories

*If the project uses Spring Data Redis repositories.*

**REP-31** — A Spring Data Redis repository is `CrudRepository<Entity, ID>` over a `@RedisHash` entity. It has no QueryDSL, `@EntityGraph` or fetch join, and the `@Column` policy (REP-14) does not apply; derived queries (REP-2 row 1) and REP-1 do. A field used in a derived query carries `@Indexed`, or the lookup loads the whole set and filters in memory (`CheckoutSessionRepository.findByMemberId`).

A `@RedisHash` entity declares every persisted field, state included, as a constructor property (`data class CheckoutSession(…, var failureCount: Int = 0, …)`). Spring Data Redis writes body properties to the hash but does not populate them on read, so a body property or a `protected set` state field comes back with its initializer value.

Rolling a `@RedisHash` entity's TTL forward uses `EXPIRE`, never `save`: `save` deletes and rewrites the key and refreshes every `@Indexed` secondary index, issuing a Redis `KEYS` per index. Redis is single-threaded, so a re-save on a hot path stalls every other client.

## 11. Migrations

**REP-32** — A committed or deployed `db/migration/V*.sql` is never edited, in content or filename: a change alters the Flyway checksum and `ddl-auto=validate` (dev/prod) fails at boot. Schema evolves through a new versioned migration — a rename too is a new `V*` with `ALTER TABLE … RENAME`. A migration not yet applied anywhere (uncommitted or undeployed) may still be edited or renumbered before merge. One feature's schema change is one migration file: it is not split into `V5`/`V6` per sub-task, and while it is unmerged each sub-task's change folds into the feature's file.

**REP-33** — A new unique constraint is named `uq_<table>_<columns>` (`uq_order_item_order_id_product_id`). Constraints in applied migrations keep their names (REP-32).
