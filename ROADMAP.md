# Polydash: Polymarket Insider Trading Detection

**Status:** Planning
**Last Updated:** 2026-01-04

## Project Overview

**Goal:** Build a research tool that monitors Polymarket for anomalous betting patterns that may indicate informed trading (fresh wallets, unusual sizing, clustered entries in niche markets).

**Target Users:** Researchers investigating prediction market integrity

**Success Metrics:**
- Real-time detection of suspicious trading patterns
- Wallet scoring system with accuracy tracking
- Dashboard for investigating alerts

**Tech Stack:**
- Phoenix 1.8.3 with LiveView 1.1
- Elixir 1.15+
- PostgreSQL 18 (Fly.io managed) with BRIN indexes for time-series
- Oban for background job processing
- ZenWebsocket for real-time data ingestion
- Req for HTTP requests

**PostgreSQL 18 Features Used:**
- `uuidv7()` for time-sortable internal IDs via `default: fragment("uuidv7()")`
- AIO (Async I/O) for bulk backfill and time-range scans (free perf gain)
- Skip scan on B-tree for "distinct wallets" and "first trade per wallet" queries
- OR clause optimization for `WHERE maker_address = X OR taker_address = X`

---

## API Research Summary

### Available APIs

| API | Base URL | Purpose | Auth Required |
|-----|----------|---------|---------------|
| **CLOB API** | https://clob.polymarket.com | Orderbook, prices, trading | No (read-only) |
| **Gamma API** | https://gamma-api.polymarket.com | Market discovery, metadata, events | No |
| **Data API** | https://data-api.polymarket.com | User positions, activity, history | No |
| **CLOB WebSocket** | wss://ws-subscriptions-clob.polymarket.com/ws/ | Real-time orderbook/prices | No |
| **RTDS WebSocket** | wss://ws-live-data.polymarket.com | Low-latency crypto prices | No |

### Subgraphs (GraphQL via Goldsky)

| Subgraph | URL | Key Entities |
|----------|-----|--------------|
| **Positions** | `.../positions-subgraph/0.0.7/gn` | UserBalance (user, asset, balance) |
| **Activity** | `.../activity-subgraph/0.0.4/gn` | Split, Merge, Redemption (stakeholder, timestamp) |
| **Orders** | `.../orderbook-subgraph/0.0.1/gn` | Order book data |
| **PNL** | `.../pnl-subgraph/0.0.14/gn` | Profit/loss tracking |
| **Open Interest** | `.../oi-subgraph/0.0.6/gn` | Market open interest |

### Rate Limits (per 10 seconds)

| Endpoint | Limit | Notes |
|----------|-------|-------|
| CLOB /book | 1,500 | Per market orderbook |
| CLOB /price | 1,500 | Current prices |
| Data API /trades | 200 | Trade history |
| Data API /positions | 150 | User positions |
| Gamma /events | 500 | Event listings |
| Gamma /markets | 300 | Market listings |
| WebSocket | Unlimited | Real-time updates |

### Key Data Structures

**Trade Object:**
```
id, taker_order_id, market, asset_id, side, size, price,
status, match_time, maker_address, transaction_hash,
maker_orders[{order_id, maker_address, matched_amount, price}]
```

**WebSocket last_trade_price:**
```
asset_id, event_type, price, side, size, timestamp, fee_rate_bps
```

**Activity Subgraph Split:**
```
id, timestamp, stakeholder, condition, amount
```

### Data Availability Assessment

| Need | Available | Source | Notes |
|------|-----------|--------|-------|
| Real-time trades | Yes | WebSocket `last_trade_price` | Per-market subscription |
| Trade history | Yes | Data API `/trades` | Filterable by maker/taker/market |
| Wallet addresses | Yes | Trade.maker_address | Polygon addresses |
| Position sizes | Yes | Positions subgraph | UserBalance by wallet |
| Market metadata | Yes | Gamma API `/markets` | Categories, volume, liquidity |
| Wallet first seen | **Partial** | Activity subgraph | Must derive from first Split/trade |
| Funding source | **External** | Polygon RPC/Polygonscan | Not in Polymarket APIs |
| Historical accuracy | **Derived** | Must compute | From resolved markets + positions |

### Limitations

1. **No direct "wallet age" endpoint** - Must derive from first transaction timestamp
2. **Funding source requires Polygon chain data** - Need separate Polygon RPC or Polygonscan API
3. **WebSocket requires per-asset subscription** - Can't subscribe to "all trades"
4. **Rate limits on historical data** - 200 req/10s for trades, 150 for positions

---

## Phase 1: Foundation & Data Model

**Goal:** Project setup, Ecto schemas, and basic API client.

**Duration:** 1 week

**Success Criteria:**
- [ ] Phoenix project with Oban configured
- [ ] Ecto schemas for markets, trades, wallets
- [ ] Basic Polymarket API client (Gamma + CLOB)
- [ ] Tests for API parsing and schema validation

---

### Task 1: Project Setup [D:2/B:8 → Priority:4.0]

**Goal:** Verify Phoenix project configuration, add Oban, configure contexts.

**Dependencies:** None

**Approach:**
1. Project already exists - verify Phoenix 1.8 configuration
2. Add Oban for background jobs
3. Configure contexts: Markets, Wallets, Alerts, Ingestion
4. Set up test environment

**Testing Requirements:**
- [ ] Database connection works
- [ ] Oban migrations run

**Acceptance Criteria:**
- [ ] `mix test` passes
- [ ] Oban queues configured

**Estimated Complexity:** Simple

---

### Task 2: Core Ecto Schemas [D:4/B:9 → Priority:2.25]

**Goal:** Create schemas for markets, trades, and wallets.

**Dependencies:** Task 1

**Approach:**
Create schemas matching Polymarket data structures:

**Markets.Market:**
- condition_id (primary key - Polymarket's market identifier)
- question, description, slug
- category, tags
- end_date, resolution_status
- volume_24h, liquidity
- inserted_at, updated_at

**Markets.Outcome:**
- token_id (primary key - Polymarket's asset_id)
- market_id (references markets)
- outcome_name (Yes/No or custom)
- current_price

**Ingestion.Trade (BRIN index on matched_at):**
- trade_id (Polymarket's id)
- market_id, token_id
- maker_address, taker_address
- side, size, price
- matched_at (timestamp - partition key)
- transaction_hash

**Wallets.Wallet:**
- address (primary key - Polygon address)
- first_seen_at
- total_trades, total_volume
- accuracy_score (computed)
- is_flagged, flag_reason
- (is_fresh? computed in Elixir from first_seen_at)

**Testing Requirements:**
- [ ] Unit: Changeset validations for all schemas
- [ ] Unit: Associations work correctly
- [ ] Edge: Invalid addresses, negative amounts

**Acceptance Criteria:**
- [ ] All schemas created with proper types
- [ ] Trade table has BRIN index on matched_at
- [ ] B-tree indexes on frequently queried columns (maker_address, market_id)
- [ ] `mix credo` passes

**Estimated Complexity:** Medium

---

### Task 3: Polymarket HTTP Client - Gamma API [D:3/B:7 → Priority:2.3]

**Goal:** Build HTTP client for Gamma API (market discovery).

**Dependencies:** Task 2

**Approach:**
Create `Polydash.Polymarket.Gamma` module using Req:

**Endpoints:**
- `GET /events` - List all events
- `GET /events/:id` - Event details
- `GET /markets` - List all markets
- `GET /markets/:id` - Market details with outcomes

**Implementation:**
- Use Req with retry and rate limiting
- Parse responses into Ecto schemas
- Handle pagination (cursor-based)

**Testing Requirements:**
- [ ] Integration: Fetch real markets from Gamma API
- [ ] Unit: Parse market response correctly
- [ ] Edge: Handle 404, rate limiting, malformed responses

**Acceptance Criteria:**
- [ ] Can fetch and parse all active markets
- [ ] Respects rate limits (300 req/10s)
- [ ] Returns `{:ok, data}` or `{:error, reason}` tuples

**Estimated Complexity:** Simple

---

### Task 4: Polymarket HTTP Client - CLOB API [D:4/B:8 → Priority:2.0]

**Goal:** Build HTTP client for CLOB API (prices, orderbooks, trades).

**Dependencies:** Task 3

**Approach:**
Create `Polydash.Polymarket.CLOB` module:

**Endpoints:**
- `GET /book?token_id=X` - Orderbook for token
- `GET /price?token_id=X` - Current price
- `GET /midpoint?token_id=X` - Midpoint price
- `GET /data/trades?maker=X&market=Y` - Trade history

**Implementation:**
- Batch requests where possible (/books, /prices)
- Parse trade history with maker/taker addresses
- Handle L2 authentication headers (for trade history)

**Testing Requirements:**
- [ ] Integration: Fetch real orderbook data
- [ ] Integration: Fetch trade history for a market
- [ ] Unit: Parse trade response correctly
- [ ] Edge: Empty orderbooks, no trades

**Acceptance Criteria:**
- [ ] Can fetch orderbook for any token
- [ ] Can fetch trade history with wallet filtering
- [ ] Rate limiting respected

**Estimated Complexity:** Medium

---

### Task 5: Polymarket HTTP Client - Subgraphs [D:4/B:7 → Priority:1.75]

**Goal:** Build GraphQL client for Goldsky subgraphs.

**Dependencies:** Task 2

**Approach:**
Create `Polydash.Polymarket.Subgraph` module:

**Queries:**
- Positions: `userBalances(where: {user: $address})`
- Activity: `splits(where: {stakeholder: $address}, orderBy: timestamp)`
- PNL: User profit/loss data

**Implementation:**
- Use Req for GraphQL POST requests
- Build query strings dynamically
- Parse into Ecto structs

**Testing Requirements:**
- [ ] Integration: Query real wallet positions
- [ ] Integration: Get wallet's first activity timestamp
- [ ] Unit: Parse GraphQL responses

**Acceptance Criteria:**
- [ ] Can query wallet positions from positions subgraph
- [ ] Can derive "first seen" from activity subgraph
- [ ] Proper error handling for GraphQL errors

**Estimated Complexity:** Medium

---

## Phase 2: Real-Time Data Ingestion

**Goal:** WebSocket-based trade ingestion and historical backfill.

**Duration:** 1-2 weeks

**Success Criteria:**
- [ ] Real-time trade ingestion via WebSocket
- [ ] Historical trade backfill from REST API
- [ ] Efficient queries with BRIN indexes

---

### Task 6: WebSocket Client for CLOB [D:5/B:9 → Priority:1.8]

**Goal:** Implement real-time trade ingestion using ZenWebsocket.

**Dependencies:** Tasks 2, 4

**Approach:**
Use ZenWebsocket patterns for CLOB WebSocket:

**Connection:**
```elixir
ZenWebsocket.Client.connect("wss://ws-subscriptions-clob.polymarket.com/ws/", [
  heartbeat_config: %{type: :ping, interval: 30_000}
])
```

**Subscription:**
```json
{
  "type": "MARKET",
  "assets_ids": ["token_id_1", "token_id_2", ...],
  "custom_feature_enabled": true
}
```

**Message Types:**
- `last_trade_price` - New trade executed
- `price_change` - Orderbook changed
- `book` - Full orderbook snapshot

**Implementation:**
- GenServer for connection management
- Dynamic subscription to active markets
- Parse and insert trades into trades table
- Handle reconnection gracefully

**Testing Requirements:**
- [ ] Integration: Connect and receive real messages
- [ ] Unit: Parse all message types correctly
- [ ] Edge: Handle disconnection/reconnection

**Acceptance Criteria:**
- [ ] Stable WebSocket connection
- [ ] Trades inserted in real-time
- [ ] Automatic reconnection on failure

**Estimated Complexity:** Complex

---

### Task 7: Trade Ingestion Pipeline [D:4/B:8 → Priority:2.0]

**Goal:** Process incoming trades and update wallet/market stats.

**Dependencies:** Task 6

**Approach:**
Create `Polydash.Ingestion.TradeProcessor`:

**On each trade:**
1. Insert trade into trades table
2. Upsert wallet record (first_seen_at, trade count, volume)
3. Update market volume stats
4. Queue for anomaly detection (Oban job)

**Implementation:**
- Use Ecto.Multi for atomic operations
- Batch inserts for performance
- Telemetry for monitoring throughput

**Testing Requirements:**
- [ ] Unit: Trade processing updates wallet stats
- [ ] Unit: First trade creates wallet record
- [ ] Integration: Throughput test with batch trades

**Acceptance Criteria:**
- [ ] Trades processed within 100ms
- [ ] Wallet stats updated atomically
- [ ] No duplicate trades inserted

**Estimated Complexity:** Medium

---

### Task 8: Historical Trade Backfill [D:5/B:7 → Priority:1.4]

**Goal:** Backfill historical trades for analysis baseline.

**Dependencies:** Tasks 4, 7

**Approach:**
Create Oban worker for backfill:

**Strategy:**
1. Fetch active markets from Gamma API
2. For each market, paginate through trade history
3. Insert trades respecting rate limits (200/10s)
4. Track backfill progress per market

**Implementation:**
- Oban job with rate limiting
- Resume from last processed trade
- Priority queue for high-volume markets

**Testing Requirements:**
- [ ] Integration: Backfill trades for one market
- [ ] Unit: Pagination works correctly
- [ ] Edge: Handle markets with no trades

**Acceptance Criteria:**
- [ ] Can backfill 7 days of trade history
- [ ] Rate limits respected
- [ ] Progress tracked and resumable

**Estimated Complexity:** Medium

---

### Task 9: Market Sync Service [D:3/B:7 → Priority:2.3]

**Goal:** Keep market metadata in sync with Gamma API.

**Dependencies:** Task 3

**Approach:**
Create `Polydash.Markets.SyncWorker` (Oban):

**Sync strategy:**
1. Fetch all markets from Gamma API
2. Upsert into local database
3. Subscribe new markets to WebSocket
4. Mark resolved markets as inactive

**Schedule:** Every 5 minutes

**Testing Requirements:**
- [ ] Integration: Sync creates new market records
- [ ] Unit: Upsert handles existing markets
- [ ] Edge: Handle Gamma API errors gracefully

**Acceptance Criteria:**
- [ ] Markets sync automatically
- [ ] New markets subscribed to WebSocket
- [ ] Resolved markets marked correctly

**Estimated Complexity:** Simple

---

## Phase 3: Wallet Scoring System

**Goal:** Build wallet analysis and scoring infrastructure.

**Duration:** 1-2 weeks

**Success Criteria:**
- [ ] Wallet age detection
- [ ] Historical accuracy tracking
- [ ] Anomaly scoring per wallet

---

### Task 10: Wallet First-Seen Detection [D:4/B:8 → Priority:2.0]

**Goal:** Determine when wallets were first active on Polymarket.

**Dependencies:** Tasks 5, 7

**Approach:**
Use Activity subgraph to find first transaction:

```graphql
query FirstActivity($address: String!) {
  splits(
    where: { stakeholder: $address }
    orderBy: timestamp
    orderDirection: asc
    first: 1
  ) {
    timestamp
  }
}
```

**Also check:** merges, redemptions for complete picture.

**Implementation:**
- Query on wallet creation/update
- Cache first_seen_at in Wallet schema
- Background job for bulk wallet analysis

**Testing Requirements:**
- [ ] Integration: Get first activity for real wallet
- [ ] Unit: Handle wallets with no activity
- [ ] Edge: Wallets only active in merges, not splits

**Acceptance Criteria:**
- [ ] first_seen_at populated for all active wallets
- [ ] Refresh on new wallet activity

**Estimated Complexity:** Medium

---

### Task 11: Wallet Accuracy Tracking [D:5/B:9 → Priority:1.8]

**Goal:** Track historical prediction accuracy per wallet.

**Dependencies:** Task 10

**Approach:**
For each resolved market:
1. Get wallet's position at resolution
2. Compare to winning outcome
3. Calculate accuracy metrics

**Metrics:**
- Total predictions (resolved markets with position)
- Correct predictions (had winning outcome)
- Weighted accuracy (by position size)
- Profit/loss (from PNL subgraph or computed)

**Implementation:**
- Oban job on market resolution
- Update wallet accuracy_score
- Store detailed prediction history

**Testing Requirements:**
- [ ] Unit: Accuracy calculation correct
- [ ] Integration: Process real resolved market
- [ ] Edge: Wallet sold before resolution

**Acceptance Criteria:**
- [ ] Accuracy tracked for all wallets with resolved positions
- [ ] Historical trend data available

**Estimated Complexity:** Complex

---

### Task 12: Wallet Behavior Profiling [D:4/B:7 → Priority:1.75]

**Goal:** Build behavioral profile for each wallet.

**Dependencies:** Tasks 10, 11

**Approach:**
Compute and store:

**Volume Metrics:**
- Average trade size
- Trade size standard deviation
- Typical market categories

**Timing Metrics:**
- Trades per day/week
- Time-of-day patterns
- Days since last trade

**Market Preferences:**
- Preferred categories (politics, sports, crypto)
- Liquidity preference (high vs low volume markets)
- Time-to-resolution preference

**Implementation:**
- Compute on trade insert (incremental)
- Full recompute job (daily)
- Store in wallet profile JSONB column

**Testing Requirements:**
- [ ] Unit: Profile metrics computed correctly
- [ ] Integration: Profile updates on new trade
- [ ] Edge: New wallet with single trade

**Acceptance Criteria:**
- [ ] Profile generated for all active wallets
- [ ] Incremental updates efficient

**Estimated Complexity:** Medium

---

### Task 13: Wallet Anomaly Score [D:5/B:9 → Priority:1.8]

**Goal:** Compute anomaly score based on wallet behavior.

**Dependencies:** Task 12

**Approach:**
Score components (0-100 each, weighted average):

**Fresh Wallet Score (weight: 0.3):**
- Age < 24h: 100
- Age < 7d: 70
- Age < 30d: 40
- Age > 30d: 0

**Size Anomaly Score (weight: 0.3):**
- Trade size vs wallet's historical mean
- Z-score > 3: 100
- Z-score > 2: 70
- Z-score > 1: 40

**Market Anomaly Score (weight: 0.2):**
- Low-liquidity market: +30
- First trade in this category: +20
- Unusual time-to-resolution: +20

**Cluster Score (weight: 0.2):**
- Part of coordinated pattern: 0-100 (computed in Phase 4)

**Testing Requirements:**
- [ ] Unit: Score computation correct
- [ ] Unit: Edge cases (new wallet, no history)
- [ ] Integration: Score real wallet trades

**Acceptance Criteria:**
- [ ] Anomaly score computed for all trades
- [ ] Configurable thresholds
- [ ] Score explains which factors contributed

**Estimated Complexity:** Medium

---

## Phase 4: Anomaly Detection

**Goal:** Detect suspicious patterns in real-time.

**Duration:** 2 weeks

**Success Criteria:**
- [ ] Volume spike detection
- [ ] Wallet clustering detection
- [ ] Time-based pattern detection
- [ ] Alert generation

---

### Task 14: Volume Spike Detection [D:4/B:8 → Priority:2.0]

**Goal:** Detect unusual volume in low-liquidity markets.

**Dependencies:** Tasks 7, 9

**Approach:**
For each market, track:
- Rolling average volume (24h, 7d)
- Current hour volume
- Spike threshold (e.g., 5x average)

**Trigger alert when:**
- Volume spike detected
- Market is low-liquidity (<$10k 24h volume)
- Significant time until resolution

**Implementation:**
- Materialized view for volume aggregates (refreshed by Oban)
- Oban job checks every 5 minutes
- Create Alert record when triggered

**Testing Requirements:**
- [ ] Unit: Spike detection logic correct
- [ ] Integration: Detect spike in test data
- [ ] Edge: New market with no history

**Acceptance Criteria:**
- [ ] Spikes detected within 10 minutes
- [ ] No false positives on high-liquidity markets
- [ ] Alert includes context (volume delta, wallets involved)

**Estimated Complexity:** Medium

---

### Task 15: Wallet Clustering Detection [D:6/B:9 → Priority:1.5]

**Goal:** Detect coordinated trading from multiple wallets.

**Dependencies:** Tasks 10, 13

**Approach:**
Detect clusters based on:

**Temporal Clustering:**
- Multiple fresh wallets trading same side
- Within short time window (< 1 hour)
- In same low-liquidity market

**Behavioral Clustering:**
- Similar trade sizes
- Similar timing patterns
- Common funding sources (if available)

**Algorithm:**
1. For each market, group trades by time window
2. Identify fresh wallets in window
3. Check for same-side concentration
4. Score cluster suspiciousness

**Implementation:**
- Oban job triggered on trade insert
- Window analysis with Postgres date_trunc + grouping
- Graph-based clustering optional (Phase 2)

**Testing Requirements:**
- [ ] Unit: Clustering algorithm correct
- [ ] Integration: Detect synthetic cluster
- [ ] Edge: Legitimate correlated trading

**Acceptance Criteria:**
- [ ] Clusters detected within 15 minutes
- [ ] Minimum cluster size configurable
- [ ] Alert includes all participating wallets

**Estimated Complexity:** Complex

---

### Task 16: Time-Based Pattern Detection [D:4/B:7 → Priority:1.75]

**Goal:** Detect activity bursts before expected events.

**Dependencies:** Task 14

**Approach:**
Track activity relative to resolution time:

**Patterns to detect:**
- Sudden activity spike 24-48h before resolution
- Unusual after-hours activity
- Weekend spikes in political markets

**Implementation:**
- Compute "time to resolution" for each trade
- Aggregate activity by time buckets
- Compare to historical baseline

**Testing Requirements:**
- [ ] Unit: Time bucket analysis correct
- [ ] Integration: Detect pre-resolution spike
- [ ] Edge: Markets with uncertain resolution time

**Acceptance Criteria:**
- [ ] Pre-resolution patterns flagged
- [ ] Time-of-day anomalies detected
- [ ] Baseline adapts to market category

**Estimated Complexity:** Medium

---

### Task 17: Alert Management System [D:3/B:8 → Priority:2.7]

**Goal:** Create, prioritize, and manage alerts.

**Dependencies:** Tasks 14-16

**Approach:**
Create `Polydash.Alerts` context:

**Alerts.Alert schema:**
- id (UUIDv7 - time-sortable, better index performance)
- alert_type (volume_spike, cluster, timing, wallet_score)
- severity (low, medium, high, critical)
- market_id, wallet_ids[]
- details (JSONB with specifics)
- status (new, investigating, dismissed, confirmed)
- created_at, acknowledged_at, resolved_at

**Implementation:**
- Deduplication (don't re-alert same pattern)
- Severity escalation (repeated patterns)
- Configurable notification thresholds

**Testing Requirements:**
- [ ] Unit: Alert creation and deduplication
- [ ] Unit: Severity calculation
- [ ] Integration: Full alert lifecycle

**Acceptance Criteria:**
- [ ] Alerts created for all anomaly types
- [ ] No duplicate alerts
- [ ] Status tracking works

**Estimated Complexity:** Simple

---

## Phase 5: LiveView Dashboard

**Goal:** Real-time dashboard for investigating alerts.

**Duration:** 2 weeks

**Success Criteria:**
- [ ] Real-time alert feed
- [ ] Market browser with volume/odds
- [ ] Wallet deep-dive view
- [ ] Category filtering

---

### Task 18: Dashboard Layout & Navigation [D:3/B:6 → Priority:2.0]

**Goal:** Create main dashboard layout with navigation.

**Dependencies:** Task 17

**Approach:**
Create `PolydashWeb.DashboardLive`:

**Layout:**
- Sidebar: Navigation, active filters
- Main: Content area (alerts, markets, wallets)
- Header: Stats summary, connection status

**Pages:**
- `/dashboard` - Alert feed (default)
- `/dashboard/markets` - Market browser
- `/dashboard/wallets/:address` - Wallet detail
- `/dashboard/alerts/:id` - Alert detail

**Implementation:**
- Use Phoenix LiveView with streams
- Tailwind CSS for styling
- Real-time updates via PubSub

**Testing Requirements:**
- [ ] Integration: Pages load correctly
- [ ] Integration: Navigation works
- [ ] Edge: Empty states

**Acceptance Criteria:**
- [ ] Responsive layout
- [ ] Navigation between pages
- [ ] Connection status indicator

**Estimated Complexity:** Simple

---

### Task 19: Real-Time Alert Feed [D:4/B:9 → Priority:2.25]

**Goal:** Live-updating alert feed with filtering.

**Dependencies:** Task 18

**Approach:**
Create alert feed component:

**Features:**
- Stream of recent alerts (newest first)
- Filter by severity, type, status
- Click to expand details
- Quick actions (dismiss, investigate)

**Real-time:**
- Subscribe to alert PubSub topic
- New alerts appear at top
- Sound/visual notification for critical

**Implementation:**
- LiveView stream for alerts
- Filter controls update stream
- Modal for alert details

**Testing Requirements:**
- [ ] Integration: Alerts display correctly
- [ ] Integration: Filters work
- [ ] Integration: Real-time updates arrive

**Acceptance Criteria:**
- [ ] Alerts update in real-time
- [ ] Filtering is instant
- [ ] Alert actions work

**Estimated Complexity:** Medium

---

### Task 20: Market Browser [D:4/B:7 → Priority:1.75]

**Goal:** Browse markets with volume and anomaly indicators.

**Dependencies:** Task 18

**Approach:**
Create market browser component:

**Features:**
- List of active markets
- Sort by volume, anomaly score, time-to-resolution
- Filter by category
- Current odds display
- Anomaly indicator (color-coded)

**Click to expand:**
- Recent trades
- Active alerts
- Volume chart

**Implementation:**
- LiveView stream for markets
- Category filter (politics, sports, crypto, etc.)
- Exclude categories I don't care about

**Testing Requirements:**
- [ ] Integration: Markets display correctly
- [ ] Integration: Sorting works
- [ ] Integration: Category filter works

**Acceptance Criteria:**
- [ ] All active markets browsable
- [ ] Anomaly scores visible
- [ ] Category exclusion persists

**Estimated Complexity:** Medium

---

### Task 21: Wallet Deep-Dive View [D:5/B:8 → Priority:1.6]

**Goal:** Detailed wallet analysis page.

**Dependencies:** Tasks 12, 18

**Approach:**
Create wallet detail page:

**Sections:**
- Header: Address, first seen, anomaly score
- Stats: Total trades, volume, accuracy
- Trade History: Paginated list with market context
- Position Breakdown: Current holdings
- Behavior Profile: Visualized metrics
- Related Wallets: Cluster associations

**Implementation:**
- Fetch wallet data on mount
- Real-time trade updates
- Link to external explorers (Polygonscan)

**Testing Requirements:**
- [ ] Integration: Wallet data loads correctly
- [ ] Integration: Trade history paginates
- [ ] Edge: Unknown wallet address

**Acceptance Criteria:**
- [ ] Full wallet analysis visible
- [ ] Trade history complete
- [ ] Links to external explorers work

**Estimated Complexity:** Medium

---

### Task 22: Alert Detail View [D:3/B:7 → Priority:2.3]

**Goal:** Detailed alert investigation page.

**Dependencies:** Task 19

**Approach:**
Create alert detail component:

**Sections:**
- Alert summary (type, severity, time)
- Market context (odds, volume, resolution)
- Involved wallets (with anomaly scores)
- Evidence timeline (trades that triggered)
- Actions (dismiss, confirm, add notes)

**Implementation:**
- Fetch alert with associations
- Timeline visualization
- Note-taking capability

**Testing Requirements:**
- [ ] Integration: Alert details load
- [ ] Integration: Actions update status
- [ ] Integration: Notes saved

**Acceptance Criteria:**
- [ ] Full alert context visible
- [ ] Investigation actions work
- [ ] Notes persist

**Estimated Complexity:** Simple

---

## Phase 6: Polish & Optimization (Future)

**Note:** Phase 6 begins after Phase 5 MVP is validated.

### Future Enhancements

- [ ] Polygon RPC integration for funding source analysis
- [ ] Historical accuracy backtesting
- [ ] ML-based anomaly scoring
- [ ] Alert notifications (email, Discord)
- [ ] Export functionality (CSV, JSON)
- [ ] Multi-user support with roles

---

## Technical Decisions

### Architecture Patterns

- **Context Boundaries:** Markets (metadata), Wallets (scoring), Alerts (detection), Ingestion (data pipeline)
- **Real-time via PubSub:** Alerts broadcast to dashboard
- **BRIN Indexes:** Trades indexed by time for efficient range queries
- **Oban for Background Jobs:** Backfill, sync, analysis

### ID Strategy

- **External IDs (from Polymarket):** Use as-is for primary keys
  - Markets: `condition_id` (hex string)
  - Tokens: `token_id` (large integer as string)
  - Trades: `trade_id` (string)
  - Wallets: `address` (Polygon address)
- **Internal IDs (our records):** Use `uuidv7()` via Postgres
  - Alerts, internal tracking records
  - Time-sortable, indexes better than UUIDv4

### Key Libraries

- **Req:** HTTP client with retry/rate limiting
- **ZenWebsocket:** WebSocket with auto-reconnect (per zen-websocket.md patterns)
- **Oban:** Reliable job processing

### Security Considerations

- No authentication needed (read-only from Polymarket)
- Wallet addresses are public data
- No user data stored (research tool only)

### Performance Considerations

- BRIN indexes for time-range queries on trades
- Materialized views for volume aggregates (Oban-refreshed)
- Stream-based LiveView for large datasets
- Rate limiting for API calls
- Table partitioning by month if volume exceeds 10M trades
- PG18 AIO: ~3x read improvement on sequential scans (backfill, dashboard queries)
- PG18 skip scan: Faster "distinct wallets" and "first trade per wallet" queries

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| API rate limiting | Medium | Medium | Respect limits, use WebSocket where possible |
| WebSocket disconnection | Medium | Medium | ZenWebsocket auto-reconnect |
| High trade volume | Low | Medium | Batch inserts, BRIN indexes, partitioning if needed |
| API changes | Low | High | Monitor Polymarket changelog, version API clients |
| Subgraph latency | Medium | Low | Use for non-critical data, cache aggressively |

---

## Open Questions

- [ ] Should we integrate Polygon RPC for funding analysis in Phase 1?
- [ ] What accuracy threshold indicates "informed trading"?
- [ ] Should alerts auto-expire after resolution?
- [ ] Multi-tenant support needed?

---

## References

- [Polymarket API Documentation](https://docs.polymarket.com)
- [CLOB API Reference](https://docs.polymarket.com/developers/CLOB/introduction)
- [Gamma API Reference](https://docs.polymarket.com/developers/gamma-markets-api/overview)
- [Polymarket Subgraphs](https://github.com/Polymarket/polymarket-subgraph)
- [ZenWebsocket Patterns](~/.claude/includes/zen-websocket.md)
