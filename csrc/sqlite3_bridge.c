#include "sqlite3_bridge.h"
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int gs_sqlite_open(const char *path, int enable_wal, void **out_db) {
    if (!path || !out_db) return -1;
    sqlite3 *db = NULL;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return rc;
    }

    if (enable_wal) {
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
    }
    sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);

    const char *schema_sql =
        "CREATE TABLE IF NOT EXISTS crm_store ("
        "    key TEXT PRIMARY KEY,"
        "    metadata TEXT CHECK(json_valid(metadata)),"
        "    data BLOB"
        ") WITHOUT ROWID;";

    char *errmsg = NULL;
    rc = sqlite3_exec(db, schema_sql, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        if (errmsg) sqlite3_free(errmsg);
        sqlite3_close(db);
        return rc;
    }

    *out_db = (void *)db;
    return SQLITE_OK;
}

int gs_sqlite_close(void *db) {
    if (!db) return SQLITE_OK;
    return sqlite3_close((sqlite3 *)db);
}

int gs_sqlite_exec(void *db, const char *sql) {
    if (!db || !sql) return -1;
    return sqlite3_exec((sqlite3 *)db, sql, NULL, NULL, NULL);
}

int gs_sqlite_put(void *db, const char *key, const char *meta, const uint8_t *data, int64_t data_len) {
    if (!db || !key) return -1;
    sqlite3 *sdb = (sqlite3 *)db;

    const char *sql =
        "INSERT INTO crm_store (key, metadata, data) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET "
        "    metadata = excluded.metadata, "
        "    data = excluded.data;";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(sdb, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_STATIC);
    if (meta && strlen(meta) > 0) {
        sqlite3_bind_text(stmt, 2, meta, -1, SQLITE_STATIC);
    } else {
        sqlite3_bind_text(stmt, 2, "{}", -1, SQLITE_STATIC);
    }

    if (data && data_len > 0) {
        sqlite3_bind_blob64(stmt, 3, data, (sqlite3_uint64)data_len, SQLITE_STATIC);
    } else {
        sqlite3_bind_blob64(stmt, 3, "", 0, SQLITE_STATIC);
    }

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc == SQLITE_DONE || rc == SQLITE_OK) return SQLITE_OK;
    return rc;
}

int gs_sqlite_get(void *db, const char *key, gs_sqlite_record_t *out_rec) {
    if (!db || !key || !out_rec) return -1;
    memset(out_rec, 0, sizeof(gs_sqlite_record_t));
    sqlite3 *sdb = (sqlite3 *)db;

    const char *sql = "SELECT key, metadata, data FROM crm_store WHERE key = ?;";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(sdb, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const char *k = (const char *)sqlite3_column_text(stmt, 0);
        const char *m = (const char *)sqlite3_column_text(stmt, 1);
        const void *d = sqlite3_column_blob(stmt, 2);
        int64_t len = (int64_t)sqlite3_column_bytes(stmt, 2);

        out_rec->key = k ? strdup(k) : strdup("");
        out_rec->metadata = m ? strdup(m) : strdup("{}");
        out_rec->data_len = len;
        if (len > 0 && d) {
            out_rec->data = (uint8_t *)malloc(len + 1);
            if (out_rec->data) {
                memcpy(out_rec->data, d, len);
                out_rec->data[len] = '\0';
            }
        } else {
            out_rec->data = NULL;
        }
        sqlite3_finalize(stmt);
        return SQLITE_OK;
    }

    sqlite3_finalize(stmt);
    return SQLITE_NOTFOUND;
}

int gs_sqlite_delete(void *db, const char *key) {
    if (!db || !key) return -1;
    sqlite3 *sdb = (sqlite3 *)db;

    const char *sql = "DELETE FROM crm_store WHERE key = ?;";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(sdb, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, key, -1, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc == SQLITE_DONE || rc == SQLITE_OK) return SQLITE_OK;
    return rc;
}

void gs_sqlite_free_record(gs_sqlite_record_t *rec) {
    if (!rec) return;
    if (rec->key) { free(rec->key); rec->key = NULL; }
    if (rec->metadata) { free(rec->metadata); rec->metadata = NULL; }
    if (rec->data) { free(rec->data); rec->data = NULL; }
    rec->data_len = 0;
}

int gs_sqlite_list(void *db, const char *prefix, int limit, int offset, gs_sqlite_record_t **out_recs, int *out_count) {
    if (!db || !out_recs || !out_count) return -1;
    *out_recs = NULL;
    *out_count = 0;
    sqlite3 *sdb = (sqlite3 *)db;

    if (limit <= 0) limit = 100;
    if (offset < 0) offset = 0;

    sqlite3_stmt *stmt = NULL;
    int rc;
    if (prefix && strlen(prefix) > 0) {
        const char *sql = "SELECT key, metadata, data FROM crm_store WHERE key LIKE ? ORDER BY key ASC LIMIT ? OFFSET ?;";
        rc = sqlite3_prepare_v2(sdb, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        char like_pat[256];
        snprintf(like_pat, sizeof(like_pat), "%s%%", prefix);
        sqlite3_bind_text(stmt, 1, like_pat, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, limit);
        sqlite3_bind_int(stmt, 3, offset);
    } else {
        const char *sql = "SELECT key, metadata, data FROM crm_store ORDER BY key ASC LIMIT ? OFFSET ?;";
        rc = sqlite3_prepare_v2(sdb, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        sqlite3_bind_int(stmt, 1, limit);
        sqlite3_bind_int(stmt, 2, offset);
    }

    int capacity = 16;
    gs_sqlite_record_t *recs = (gs_sqlite_record_t *)malloc(capacity * sizeof(gs_sqlite_record_t));
    int count = 0;

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count >= capacity) {
            capacity *= 2;
            recs = (gs_sqlite_record_t *)realloc(recs, capacity * sizeof(gs_sqlite_record_t));
        }
        const char *k = (const char *)sqlite3_column_text(stmt, 0);
        const char *m = (const char *)sqlite3_column_text(stmt, 1);
        const void *d = sqlite3_column_blob(stmt, 2);
        int64_t len = (int64_t)sqlite3_column_bytes(stmt, 2);

        recs[count].key = k ? strdup(k) : strdup("");
        recs[count].metadata = m ? strdup(m) : strdup("{}");
        recs[count].data_len = len;
        if (len > 0 && d) {
            recs[count].data = (uint8_t *)malloc(len + 1);
            if (recs[count].data) {
                memcpy(recs[count].data, d, len);
                recs[count].data[len] = '\0';
            }
        } else {
            recs[count].data = NULL;
        }
        count++;
    }

    sqlite3_finalize(stmt);
    *out_recs = recs;
    *out_count = count;
    return SQLITE_OK;
}

void gs_sqlite_free_records(gs_sqlite_record_t *recs, int count) {
    if (!recs) return;
    for (int i = 0; i < count; i++) {
        gs_sqlite_free_record(&recs[i]);
    }
    free(recs);
}
