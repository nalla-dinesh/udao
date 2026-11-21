// phase-02
// Versioned DDL for the encrypted ledger. **DB_VERSION = 1** — the
// bootstrap schema. Every later change ships as a migration step in
// `migrations.dart` plus DDL constants here (never edited in place).
//
// Conventions: TEXT ids, INTEGER epoch-ms timestamps, INTEGER paise
// money, REAL confidence, 0/1 bools. All access parameterised.
abstract final class UdaoSchema {
  /// Bump ONLY together with a migration step.
  static const int dbVersion = 1;

  /// Ordered CREATE TABLE statements (children after parents).
  static const List<String> createTables = <String>[
    '''
    CREATE TABLE category (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      icon TEXT NOT NULL,
      color_role TEXT NOT NULL,
      is_essential INTEGER NOT NULL DEFAULT 0,
      parent_id TEXT NULL REFERENCES category (id),
      sort INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE txn (
      id TEXT NOT NULL PRIMARY KEY,
      amount INTEGER NOT NULL,
      direction TEXT NOT NULL,
      source TEXT NOT NULL,
      raw_text TEXT NOT NULL,
      merchant_raw TEXT NOT NULL,
      merchant_clean TEXT NOT NULL,
      bank_or_app TEXT NOT NULL,
      category_id TEXT NULL REFERENCES category (id),
      ref_no TEXT NULL,
      vpa TEXT NULL,
      occurred_at INTEGER NOT NULL,
      captured_at INTEGER NOT NULL,
      confidence REAL NOT NULL,
      dedup_key TEXT NOT NULL,
      note TEXT NULL
    )
    ''',
    '''
    CREATE TABLE budget (
      id TEXT NOT NULL PRIMARY KEY,
      category_id TEXT NULL REFERENCES category (id),
      limit_paise INTEGER NOT NULL,
      period TEXT NOT NULL,
      rollover INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE subscription (
      id TEXT NOT NULL PRIMARY KEY,
      merchant_clean TEXT NOT NULL,
      amount_paise INTEGER NOT NULL,
      cadence_days INTEGER NOT NULL,
      last_seen INTEGER NOT NULL,
      status TEXT NOT NULL,
      mandate_ref TEXT NULL
    )
    ''',
    '''
    CREATE TABLE streak_state (
      id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
      current_start INTEGER NULL,
      length INTEGER NOT NULL DEFAULT 0,
      freezes_left INTEGER NOT NULL DEFAULT 2,
      longest INTEGER NOT NULL DEFAULT 0,
      last_no_spend_date INTEGER NULL
    )
    ''',
    '''
    CREATE TABLE badge (
      id TEXT NOT NULL PRIMARY KEY,
      unlocked_at INTEGER NULL,
      seen INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE challenge_progress (
      id TEXT NOT NULL PRIMARY KEY,
      metric TEXT NOT NULL,
      current INTEGER NOT NULL,
      target INTEGER NOT NULL,
      completed_at INTEGER NULL
    )
    ''',
    '''
    CREATE TABLE jar (
      id TEXT NOT NULL PRIMARY KEY,
      label TEXT NOT NULL,
      goal_paise INTEGER NOT NULL,
      saved_paise INTEGER NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE roast_entry (
      id TEXT NOT NULL PRIMARY KEY,
      template_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      surface TEXT NOT NULL,
      text TEXT NOT NULL,
      txn_context TEXT NULL
    )
    ''',
    '''
    CREATE TABLE capture_event (
      id TEXT NOT NULL PRIMARY KEY,
      source TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      parsed INTEGER NOT NULL DEFAULT 0,
      deduped INTEGER NOT NULL DEFAULT 0,
      confidence REAL NOT NULL DEFAULT 0,
      raw_hash TEXT NOT NULL,
      raw_text TEXT NULL,
      parser_id TEXT NULL,
      drop_reason TEXT NULL
    )
    ''',
    '''
    CREATE TABLE pending_review (
      id TEXT NOT NULL PRIMARY KEY,
      source TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      raw_text TEXT NOT NULL,
      amount INTEGER NULL,
      direction TEXT NULL,
      merchant_raw TEXT NULL,
      merchant_clean TEXT NULL,
      bank_or_app TEXT NULL,
      ref_no TEXT NULL,
      vpa TEXT NULL,
      confidence REAL NOT NULL,
      parser_id TEXT NULL,
      dedup_key TEXT NULL,
      resolved INTEGER NOT NULL DEFAULT 0,
      resolution TEXT NULL,
      resolved_at INTEGER NULL
    )
    ''',
    '''
    CREATE TABLE embedding (
      txn_id TEXT NOT NULL PRIMARY KEY REFERENCES txn (id) ON DELETE CASCADE,
      vector BLOB NOT NULL,
      model_tag TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE kv (
      key TEXT NOT NULL PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
  ];

  /// Ordered CREATE (UNIQUE) INDEX statements.
  static const List<String> createIndexes = <String>[
    'CREATE UNIQUE INDEX uq_txn_dedup ON txn (dedup_key)',
    'CREATE INDEX idx_txn_occurred_at ON txn (occurred_at)',
    'CREATE INDEX idx_txn_category ON txn (category_id)',
    'CREATE INDEX idx_txn_source ON txn (source)',
    'CREATE INDEX idx_capture_received_at ON capture_event (received_at)',
    'CREATE INDEX idx_review_pending ON pending_review (resolved, received_at)',
    'CREATE INDEX idx_sub_merchant ON subscription (merchant_clean)',
  ];

  /// Tables wiped by DPDP delete, children first (FK-safe order).
  static const List<String> wipeOrder = <String>[
    'embedding',
    'txn',
    'pending_review',
    'capture_event',
    'roast_entry',
    'challenge_progress',
    'badge',
    'jar',
    'subscription',
    'budget',
    'streak_state',
    'category',
    'kv',
  ];

  /// Reserved `kv` keys — collisions with these are a programming error.
  static const List<String> reservedKvKeys = <String>[
    'schema.welcome_done', // Phase-03 replays priming after reinstall
    'agent.last_boot_ms',
    'capture.listener_state',
    'roast.daily_seed',
    'khel.challenge_set',
  ];
}
