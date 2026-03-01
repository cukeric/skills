# CQRS Patterns Reference

## Overview

CQRS (Command Query Responsibility Segregation) separates read and write operations into different models, allowing each to be optimized independently.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Command    │────▶│  Write Store │────▶│   Events     │
│  (Create,    │     │  (Source of  │     │  Published   │
│   Update)    │     │   Truth)     │     │              │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    Query     │◀────│  Read Store  │◀────│  Projector   │
│  (List, Get, │     │  (Optimized  │     │  (Builds     │
│   Search)    │     │   Views)     │     │   Views)     │
└──────────────┘     └──────────────┘     └──────────────┘
```

---

## When to Use CQRS

### ✅ Good Fit

- Read and write patterns are very different (e.g., complex writes, denormalized reads)
- You need multiple read projections of the same data
- Read and write workloads need independent scaling
- You need a complete audit trail (event sourcing)
- Domain complexity justifies the overhead

### ❌ Bad Fit

- Simple CRUD applications
- Small team without event infrastructure experience
- Read/write patterns are similar
- Strong consistency is required everywhere (no eventual consistency tolerance)

---

## Command Pattern

```typescript
// Commands represent intentions to change state
interface Command {
  type: string
  payload: unknown
  metadata: {
    userId: string
    correlationId: string
    timestamp: string
  }
}

// Command handlers validate and execute
interface CommandHandler<T extends Command> {
  handle(command: T): Promise<DomainEvent[]>
}

// Example: Create Order Command
interface CreateOrderCommand extends Command {
  type: 'CreateOrder'
  payload: {
    customerId: string
    items: Array<{ productId: string; quantity: number }>
    shippingAddress: Address
  }
}

class CreateOrderHandler implements CommandHandler<CreateOrderCommand> {
  constructor(
    private orderRepo: OrderRepository,
    private productService: ProductService,
    private eventBus: EventBus
  ) {}

  async handle(command: CreateOrderCommand): Promise<DomainEvent[]> {
    // 1. Validate business rules
    const customer = await this.orderRepo.getCustomer(command.payload.customerId)
    if (!customer) throw new Error('Customer not found')

    // 2. Check inventory
    for (const item of command.payload.items) {
      const available = await this.productService.checkStock(item.productId, item.quantity)
      if (!available) throw new Error(`Insufficient stock for ${item.productId}`)
    }

    // 3. Calculate totals
    const items = await this.productService.resolveItems(command.payload.items)
    const totalCents = items.reduce((sum, i) => sum + i.priceCents * i.quantity, 0)

    // 4. Create aggregate
    const order = Order.create({
      customerId: command.payload.customerId,
      items,
      totalCents,
      shippingAddress: command.payload.shippingAddress,
    })

    // 5. Persist write model
    await this.orderRepo.save(order)

    // 6. Publish events
    const events = order.getUncommittedEvents()
    await this.eventBus.publishAll(events)

    return events
  }
}
```

---

## Read Projections

```typescript
// Projections build optimized read models from events
class OrderListProjection {
  constructor(private readDb: ReadDatabase) {}

  async handle(event: DomainEvent) {
    switch (event.type) {
      case 'order.created':
        await this.readDb.orderSummaries.upsert({
          id: event.data.orderId,
          customerName: event.data.customerName,
          totalCents: event.data.totalCents,
          itemCount: event.data.items.length,
          status: 'pending',
          createdAt: event.timestamp,
        })
        break

      case 'order.shipped':
        await this.readDb.orderSummaries.update(event.data.orderId, {
          status: 'shipped',
          shippedAt: event.timestamp,
          trackingNumber: event.data.trackingNumber,
        })
        break

      case 'order.cancelled':
        await this.readDb.orderSummaries.update(event.data.orderId, {
          status: 'cancelled',
          cancelledAt: event.timestamp,
          cancelReason: event.data.reason,
        })
        break
    }
  }
}

// Dashboard projection (different read model from same events)
class DashboardProjection {
  async handle(event: DomainEvent) {
    switch (event.type) {
      case 'order.created':
        await this.readDb.dashboardStats.increment('totalOrders')
        await this.readDb.dashboardStats.incrementBy('revenue', event.data.totalCents)
        break

      case 'order.cancelled':
        await this.readDb.dashboardStats.increment('cancelledOrders')
        break
    }
  }
}
```

---

## Event Sourcing

Event sourcing stores the full history of state changes as events, rather than storing current state.

```typescript
// Event store
interface EventStore {
  append(streamId: string, events: DomainEvent[], expectedVersion: number): Promise<void>
  getStream(streamId: string, fromVersion?: number): Promise<DomainEvent[]>
}

// Aggregate rebuilt from events
class Order {
  private state: OrderState = { status: 'draft', items: [], totalCents: 0 }
  private version = 0
  private uncommittedEvents: DomainEvent[] = []

  // Rebuild aggregate from event history
  static fromEvents(events: DomainEvent[]): Order {
    const order = new Order()
    for (const event of events) {
      order.apply(event, false)
    }
    return order
  }

  // Apply event to update internal state
  private apply(event: DomainEvent, isNew: boolean) {
    switch (event.type) {
      case 'order.created':
        this.state = {
          id: event.data.orderId,
          status: 'pending',
          items: event.data.items,
          totalCents: event.data.totalCents,
          customerId: event.data.customerId,
        }
        break
      case 'order.shipped':
        this.state.status = 'shipped'
        break
      case 'order.cancelled':
        this.state.status = 'cancelled'
        break
    }

    this.version++
    if (isNew) this.uncommittedEvents.push(event)
  }

  // Business method that generates events
  ship(trackingNumber: string) {
    if (this.state.status !== 'pending') {
      throw new Error('Can only ship pending orders')
    }

    this.apply({
      id: generateId(),
      type: 'order.shipped',
      version: 1,
      timestamp: new Date().toISOString(),
      source: 'order-service',
      data: { orderId: this.state.id, trackingNumber },
    } as DomainEvent, true)
  }

  getUncommittedEvents() { return this.uncommittedEvents }
  getVersion() { return this.version }
}
```

---

## Saga Pattern (Process Manager)

Sagas coordinate long-running business processes across multiple services.

```typescript
// Order fulfillment saga
class OrderFulfillmentSaga {
  constructor(
    private paymentService: PaymentService,
    private inventoryService: InventoryService,
    private shippingService: ShippingService,
    private eventBus: EventBus
  ) {}

  async handle(event: DomainEvent) {
    switch (event.type) {
      case 'order.created':
        // Step 1: Reserve inventory
        try {
          await this.inventoryService.reserve(event.data.items)
          await this.eventBus.publish({ type: 'inventory.reserved', data: event.data })
        } catch {
          await this.eventBus.publish({ type: 'order.cancelled', data: { reason: 'Out of stock' } })
        }
        break

      case 'inventory.reserved':
        // Step 2: Process payment
        try {
          await this.paymentService.charge(event.data.customerId, event.data.totalCents)
          await this.eventBus.publish({ type: 'payment.processed', data: event.data })
        } catch {
          // Compensate: release inventory
          await this.inventoryService.release(event.data.items)
          await this.eventBus.publish({ type: 'order.cancelled', data: { reason: 'Payment failed' } })
        }
        break

      case 'payment.processed':
        // Step 3: Create shipment
        await this.shippingService.createShipment(event.data)
        break

      case 'payment.failed':
        // Compensating action
        await this.inventoryService.release(event.data.items)
        break
    }
  }
}
```

---

## Eventual Consistency Handling

```typescript
// UI pattern: show optimistic state while projection catches up
function OrderList() {
  const { data: orders } = useQuery({
    queryKey: ['orders'],
    refetchInterval: 2000, // Poll for projection updates
  })

  const createOrder = useMutation({
    mutationFn: (data) => api.post('/api/v1/commands/create-order', data),
    // Optimistic update: add to list immediately
    onMutate: async (newOrder) => {
      await queryClient.cancelQueries({ queryKey: ['orders'] })
      const previous = queryClient.getQueryData(['orders'])
      queryClient.setQueryData(['orders'], (old) => [
        ...old,
        { ...newOrder, status: 'processing', _optimistic: true },
      ])
      return { previous }
    },
    onError: (err, vars, context) => {
      queryClient.setQueryData(['orders'], context.previous)
    },
  })
}
```

---

## CQRS Checklist

- [ ] Clear separation between command and query models
- [ ] Commands validated before execution (business rules)
- [ ] Events published after successful command execution
- [ ] Read projections built from events
- [ ] Eventual consistency latency acceptable for the use case
- [ ] UI handles eventual consistency (optimistic updates, polling)
- [ ] Event replay capability (rebuild projections from scratch)
- [ ] Saga/process manager for cross-service workflows
- [ ] Compensating actions defined for each saga step
- [ ] Event versioning strategy (backward compatibility)
