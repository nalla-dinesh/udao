# ADR-0004 — SQLite (SQLCipher) as the single store, including vectors

- **Status:** Accepted (Phase 00; wiring lands in Phase 02)
- **Date:** 2026-10-27

## Context

UDAO needs: (a) encryption at rest for financial data; (b) relational
queries (ledger filters, category rollups, salary-window slices); (c) a
place to keep small embedding vectors for the AI core's memory and the
roast engine's template selection; (d) zero network services.

Candidates: ObjectBox (fast, encrypted variant commercial-licensed on
some tiers, vector search in beta), Isar (hibernating maintenance),
Realm (dynamo license + cloud push), Hive (no relational queries),
Drift/SQLite (relational, mature, but plain).

## Decision

1. **One SQLCipher-encrypted SQLite database** (`sqflite` +
   `sqlcipher_flutter_libs`, opened with a password) is the single store.
2. The DB key is generated once and held in `flutter_secure_storage`
   (Android Keystore-backed).
3. **Embeddings live in the same DB as BLOBs** (`Float32List` bytes);
   similarity is Dart-side cosine over candidate rows.
4. Schema migrations are hand-versioned with tests (ADR-0003's no-codegen
   stance applies to migration code too).

## Consequences

**Positive:** one store to back up/ wipe (DPDP delete = drop DB);
relational power for the ledger; encryption for free; no extra binary.

**Negative:** Dart cosine is O(n) per query — fine at UDAO's scale
(a user generates ≤10k transactions and ≤10k embeddings in a lifetime;
10k × 384 floats ≈ 15 MB scanned in a few ms), but not a vector DB;
hand-written migrations are the biggest long-term risk.

**Mitigations:** user-versioned `PRAGMA user_version` migrations with
before/after fixture tests (Phase 02); revisit a real vector index only
if profile data proves need.
