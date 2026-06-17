---
title: Google SRE   Critical User Journey
---
<!-- generated from ~/peter-llm-wiki; edit source there, not here -->

# Critical User Journey (CUJ)

> **CUJ = the critical path a user takes to accomplish something important.**
>
> If this path breaks, users perceive the service as unhealthy, even when low-level infrastructure metrics still look normal.

Google SRE's SLO thinking starts from user experience:

> **What do users care about?**

The answer to that question should drive which measurements become SLIs and which targets become SLOs.

---

## CUJ -> SLI -> SLO

The basic flow is:

```text
CUJ -> SLI -> SLO
```

- **CUJ** defines the user journey we care about.
- **SLI** defines how we measure whether that journey is working.
- **SLO** defines how good is good enough.

Example:

| Layer | Question | Generic Example |
| --- | --- | --- |
| CUJ | What does the user need to do? | A user submits a request and receives the expected result. |
| SLI | How do we measure that journey? | Request success rate, request latency, result correctness. |
| SLO | What target do we expect? | 99.9% successful requests, p95 latency below a defined threshold. |

The key point:

> **We do not start by asking "what metrics do we already have?"**
>
> We start by asking "what user journey matters?" and then decide what should be measured.

---

## Metric vs SLI

> **An SLI is a metric deliberately selected because it reflects user experience.**

The difference:

- **Metric** = raw system data.
- **SLI** = a metric, or derived measurement, chosen because it tells us whether users are having a good experience.

Examples:

| Metric | Is it automatically an SLI? | Why |
| --- | --- | --- |
| CPU usage | No | Useful for debugging, but users do not directly care about CPU. |
| Memory usage | No | Useful for capacity and troubleshooting, but not usually the journey itself. |
| Pod restart count | No | Useful as a drill-down signal, but not directly user-facing. |
| Request success rate | Often yes | Users care whether requests succeed. |
| Request p95 latency | Often yes | Users care whether the service feels slow. |
| Data freshness age | Often yes for data products | Users care when displayed data is stale. |

This means a dashboard can contain many metrics, but only a smaller set should be treated as SLIs.

---

## Google SRE Measurement Guidance

Google SRE commonly groups SLIs by the type of system being measured.

### User-Facing Serving Systems

For systems that directly serve user requests, the most common SLI categories are:

1. **Availability**
   - Can the user successfully complete the request?
   - Example measurement: successful requests / total requests.

2. **Latency**
   - How long does a successful request take?
   - Example measurement: p95 or p99 latency for successful requests.

3. **Throughput**
   - How much work is the system handling?
   - Example measurement: requests per second or requests per minute.

4. **Correctness**
   - Did the system return the right result?
   - Example measurement: valid response shape, complete data, successful downstream action.

### Storage Systems

For systems that store or retrieve data, useful SLI categories include:

1. **Latency**
   - How long do reads, writes, or queries take?

2. **Availability**
   - Can clients successfully read, write, or query?

3. **Durability**
   - Is committed data preserved?

4. **Correctness**
   - Does the returned data match what the application and user expect?

## How To Identify CUJs

Start with the user journey, not the infrastructure.

Ask:

> **If this breaks, will users notice quickly?**

If yes, it is probably a CUJ or part of a CUJ.

### 5 Questions To Ask

1. **Where can the user get blocked or give up?**
   - Login failure
   - Permission failure
   - Empty or stale result
   - Failed download
   - No final result after an action starts

2. **Which parts can we measure today, and which parts can we not measure yet?**
   - Some request metrics may already exist.
   - Dependency latency may be missing.
   - Data correctness may require new instrumentation or synthetic checks.

3. **Which steps are common across many journeys?**
   - Authentication
   - Authorization
   - Shared APIs
   - Shared storage
   - External dependencies

4. **Which signals can be aggregated, and which must be separated?**
   - Overall availability can often be aggregated.
   - Critical routes and dependency paths may need separate SLIs.

5. **Which steps have strict dependencies?**
   - User action -> request accepted -> service work completes -> user sees final state.

---

## What A Good CUJ Description Contains

A good CUJ description should make the user path explicit.

Generic shape:

```text
user action
-> entry point
-> service logic
-> data store / queue / dependency
-> response or async completion
-> user-visible result
```

For each CUJ, identify:

- What the user is trying to do.
- What success looks like to the user.
- Which systems are involved.
- Which parts are synchronous.
- Which parts are asynchronous.
- Which parts are measurable today.
- Which parts need new instrumentation.

---

## After Identifying CUJs

Once we identify a CUJ, the next steps are:

1. Identify the user-visible success event.
2. Decide how to measure that event.
3. Turn that measurement into an SLI.
4. Decide the SLO target.
5. Use the SLO to design dashboards, alerts, and runbooks.

In short:

```text
CUJ -> user-visible event -> SLI -> SLO -> dashboard / alert / runbook
```

The purpose of CUJ work is to create shared language between Product, Development, and SRE:

> **What matters to users, how do we measure it, and how good does it need to be?**
