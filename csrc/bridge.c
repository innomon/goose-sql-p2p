#include <sqlite3.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

/* Helper to convert sl_u8 to null-terminated C string */
static char *sl_to_cstr(sl_u8 s) {
    char *p = (char *)malloc(s.len + 1);
    if (!p) return NULL;
    if (s.len > 0 && s.data) {
        memcpy(p, s.data, s.len);
    }
    p[s.len] = '\0';
    return p;
}

/* ========================================================================= */
/* SQLite Bridge Implementation                                              */
/* ========================================================================= */

/* Helper to ensure parent directory exists */
static void ensure_parent_dirs(const char *filepath) {
    if (!filepath) return;
    char temp[1024];
    strncpy(temp, filepath, sizeof(temp) - 1);
    temp[sizeof(temp) - 1] = '\0';
    char *slash = strrchr(temp, '/');
    if (slash) {
        *slash = '\0';
        char cmd[2048];
        snprintf(cmd, sizeof(cmd), "mkdir -p \"%s\"", temp);
        if (system(cmd) != 0) {
            // directory creation attempted
        }
    }
}

int32_t gs_db_open(sl_u8 path, uint8_t enable_wal, uint64_t *out_handle) {
    if (!out_handle) return -1;
    char *cpath = sl_to_cstr(path);
    if (!cpath) return -1;

    ensure_parent_dirs(cpath);

    sqlite3 *db = NULL;
    int rc = sqlite3_open(cpath, &db);
    free(cpath);

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

    *out_handle = (uint64_t)(uintptr_t)db;
    return SQLITE_OK;
}

int32_t gs_db_close(uint64_t handle) {
    if (!handle) return SQLITE_OK;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;
    return sqlite3_close(db);
}

int32_t gs_db_exec(uint64_t handle, sl_u8 sql) {
    if (!handle) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;
    char *csql = sl_to_cstr(sql);
    if (!csql) return -1;

    int rc = sqlite3_exec(db, csql, NULL, NULL, NULL);
    free(csql);
    return rc;
}

int32_t gs_db_put(uint64_t handle, sl_u8 key, sl_u8 meta, sl_u8 data) {
    if (!handle) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;

    const char *sql =
        "INSERT INTO crm_store (key, metadata, data) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET "
        "    metadata = excluded.metadata, "
        "    data = excluded.data;";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, (const char *)key.data, (int)key.len, SQLITE_STATIC);

    if (meta.len > 0) {
        sqlite3_bind_text(stmt, 2, (const char *)meta.data, (int)meta.len, SQLITE_STATIC);
    } else {
        sqlite3_bind_text(stmt, 2, "{}", 2, SQLITE_STATIC);
    }

    if (data.len > 0) {
        sqlite3_bind_blob64(stmt, 3, data.data, (sqlite3_uint64)data.len, SQLITE_STATIC);
    } else {
        sqlite3_bind_blob64(stmt, 3, "", 0, SQLITE_STATIC);
    }

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc == SQLITE_DONE || rc == SQLITE_OK) return SQLITE_OK;
    return rc;
}

int32_t gs_db_get(uint64_t handle, sl_u8 key, gs_rref out_meta, gs_rref out_data) {
    if (!handle) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;

    const char *sql = "SELECT metadata, data FROM crm_store WHERE key = ?;";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, (const char *)key.data, (int)key.len, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const char *m = (const char *)sqlite3_column_text(stmt, 0);
        int m_len = sqlite3_column_bytes(stmt, 0);
        const void *d = sqlite3_column_blob(stmt, 1);
        int d_len = sqlite3_column_bytes(stmt, 1);

        if (m && m_len > 0) {
            gs_bld_append(out_meta, (const uint8_t *)m, (size_t)m_len);
        } else {
            gs_bld_append(out_meta, (const uint8_t *)"{}", 2);
        }

        if (d && d_len > 0) {
            gs_bld_append(out_data, (const uint8_t *)d, (size_t)d_len);
        }

        sqlite3_finalize(stmt);
        return SQLITE_OK;
    }

    sqlite3_finalize(stmt);
    return 1; // 1 = NOT FOUND
}

int32_t gs_db_delete(uint64_t handle, sl_u8 key) {
    if (!handle) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;

    const char *sql = "DELETE FROM crm_store WHERE key = ?;";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return rc;

    sqlite3_bind_text(stmt, 1, (const char *)key.data, (int)key.len, SQLITE_STATIC);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc == SQLITE_DONE || rc == SQLITE_OK) return SQLITE_OK;
    return rc;
}

int32_t gs_db_list(uint64_t handle, sl_u8 prefix, int32_t limit, int32_t offset, gs_rref out_json) {
    if (!handle) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;

    if (limit <= 0) limit = 100;
    if (offset < 0) offset = 0;

    sqlite3_stmt *stmt = NULL;
    int rc;
    if (prefix.len > 0) {
        const char *sql = "SELECT key, metadata, data FROM crm_store WHERE key LIKE ? ORDER BY key ASC LIMIT ? OFFSET ?;";
        rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;

        char like_pat[256];
        int plen = prefix.len < 250 ? (int)prefix.len : 250;
        memcpy(like_pat, prefix.data, plen);
        like_pat[plen] = '%';
        like_pat[plen + 1] = '\0';

        sqlite3_bind_text(stmt, 1, like_pat, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, limit);
        sqlite3_bind_int(stmt, 3, offset);
    } else {
        const char *sql = "SELECT key, metadata, data FROM crm_store ORDER BY key ASC LIMIT ? OFFSET ?;";
        rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        sqlite3_bind_int(stmt, 1, limit);
        sqlite3_bind_int(stmt, 2, offset);
    }

    gs_bld_append(out_json, (const uint8_t *)"[", 1);
    int count = 0;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count > 0) {
            gs_bld_append(out_json, (const uint8_t *)",", 1);
        }
        const char *k = (const char *)sqlite3_column_text(stmt, 0);
        int klen = sqlite3_column_bytes(stmt, 0);
        const char *m = (const char *)sqlite3_column_text(stmt, 1);
        int mlen = sqlite3_column_bytes(stmt, 1);
        const char *d = (const char *)sqlite3_column_text(stmt, 2);
        int dlen = sqlite3_column_bytes(stmt, 2);

        gs_bld_append(out_json, (const uint8_t *)"{\"key\":\"", 8);
        if (k && klen > 0) gs_bld_append(out_json, (const uint8_t *)k, (size_t)klen);
        gs_bld_append(out_json, (const uint8_t *)"\",\"metadata\":", 13);
        if (m && mlen > 0) {
            gs_bld_append(out_json, (const uint8_t *)m, (size_t)mlen);
        } else {
            gs_bld_append(out_json, (const uint8_t *)"{}", 2);
        }
        gs_bld_append(out_json, (const uint8_t *)",\"data\":\"", 9);
        if (d && dlen > 0) {
            for (int i = 0; i < dlen; i++) {
                char c = d[i];
                if (c == '"') gs_bld_append(out_json, (const uint8_t *)"\\\"", 2);
                else if (c == '\\') gs_bld_append(out_json, (const uint8_t *)"\\\\", 2);
                else if (c == '\n') gs_bld_append(out_json, (const uint8_t *)"\\n", 2);
                else if (c == '\r') gs_bld_append(out_json, (const uint8_t *)"\\r", 2);
                else if (c == '\t') gs_bld_append(out_json, (const uint8_t *)"\\t", 2);
                else gs_bld_append(out_json, (const uint8_t *)&c, 1);
            }
        }
        gs_bld_append(out_json, (const uint8_t *)"\"}", 2);
        count++;
    }
    gs_bld_append(out_json, (const uint8_t *)"]", 1);

    sqlite3_finalize(stmt);
    return SQLITE_OK;
}

/* Raw SQL Query and Execution with JSON, ASCII Table, and CSV formatters */
int32_t gs_db_query_raw(uint64_t handle, sl_u8 sql, sl_u8 format, gs_rref out_result) {
    if (!handle || sql.len == 0 || !sql.data) return -1;
    sqlite3 *db = (sqlite3 *)(uintptr_t)handle;

    int fmt_mode = 0; // 0 = JSON, 1 = TABLE, 2 = CSV
    if (format.len >= 3) {
        if (format.len >= 5 && strncmp((const char *)format.data, "table", 5) == 0) fmt_mode = 1;
        else if (strncmp((const char *)format.data, "tab", 3) == 0) fmt_mode = 1;
        else if (strncmp((const char *)format.data, "csv", 3) == 0) fmt_mode = 2;
    }

    char *csql = sl_to_cstr(sql);
    if (!csql) return -1;

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(db, csql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        const char *err = sqlite3_errmsg(db);
        if (fmt_mode == 0) {
            char err_json[512];
            snprintf(err_json, sizeof(err_json), "{\"status\":\"error\",\"error\":\"%s\"}", err ? err : "unknown error");
            gs_bld_append(out_result, (const uint8_t *)err_json, strlen(err_json));
        } else {
            char err_txt[512];
            snprintf(err_txt, sizeof(err_txt), "Error: %s", err ? err : "unknown error");
            gs_bld_append(out_result, (const uint8_t *)err_txt, strlen(err_txt));
        }
        free(csql);
        return rc;
    }

    int num_cols = sqlite3_column_count(stmt);

    if (num_cols == 0) {
        // DDL / DML non-query statement
        int total_before = sqlite3_total_changes(db);
        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
            const char *err = sqlite3_errmsg(db);
            if (fmt_mode == 0) {
                char err_json[512];
                snprintf(err_json, sizeof(err_json), "{\"status\":\"error\",\"error\":\"%s\"}", err ? err : "execution error");
                gs_bld_append(out_result, (const uint8_t *)err_json, strlen(err_json));
            } else {
                char err_txt[512];
                snprintf(err_txt, sizeof(err_txt), "Error: %s", err ? err : "execution error");
                gs_bld_append(out_result, (const uint8_t *)err_txt, strlen(err_txt));
            }
            sqlite3_finalize(stmt);
            free(csql);
            return rc;
        }

        int changes = sqlite3_total_changes(db) - total_before;
        if (fmt_mode == 0) {
            char res_json[128];
            snprintf(res_json, sizeof(res_json), "{\"status\":\"ok\",\"rows_affected\":%d}", changes);
            gs_bld_append(out_result, (const uint8_t *)res_json, strlen(res_json));
        } else if (fmt_mode == 1) {
            char res_tbl[128];
            snprintf(res_tbl, sizeof(res_tbl), "OK: %d row(s) affected.", changes);
            gs_bld_append(out_result, (const uint8_t *)res_tbl, strlen(res_tbl));
        } else {
            char res_csv[128];
            snprintf(res_csv, sizeof(res_csv), "status,rows_affected\nok,%d", changes);
            gs_bld_append(out_result, (const uint8_t *)res_csv, strlen(res_csv));
        }

        sqlite3_finalize(stmt);
        free(csql);
        return SQLITE_OK;
    }

    // Query returning rows
    if (fmt_mode == 0) {
        // JSON format
        gs_bld_append(out_result, (const uint8_t *)"[", 1);
        int row_count = 0;
        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            if (row_count > 0) {
                gs_bld_append(out_result, (const uint8_t *)",", 1);
            }
            gs_bld_append(out_result, (const uint8_t *)"{", 1);
            for (int col = 0; col < num_cols; col++) {
                if (col > 0) {
                    gs_bld_append(out_result, (const uint8_t *)",", 1);
                }
                const char *col_name = sqlite3_column_name(stmt, col);
                gs_bld_append(out_result, (const uint8_t *)"\"", 1);
                if (col_name) gs_bld_append(out_result, (const uint8_t *)col_name, strlen(col_name));
                gs_bld_append(out_result, (const uint8_t *)"\":", 2);

                int type = sqlite3_column_type(stmt, col);
                if (type == SQLITE_NULL) {
                    gs_bld_append(out_result, (const uint8_t *)"null", 4);
                } else if (type == SQLITE_INTEGER) {
                    sqlite3_int64 ival = sqlite3_column_int64(stmt, col);
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%lld", (long long)ival);
                    gs_bld_append(out_result, (const uint8_t *)buf, strlen(buf));
                } else if (type == SQLITE_FLOAT) {
                    double fval = sqlite3_column_double(stmt, col);
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%g", fval);
                    gs_bld_append(out_result, (const uint8_t *)buf, strlen(buf));
                } else {
                    const char *tval = (const char *)sqlite3_column_text(stmt, col);
                    int tlen = sqlite3_column_bytes(stmt, col);
                    gs_bld_append(out_result, (const uint8_t *)"\"", 1);
                    if (tval && tlen > 0) {
                        for (int i = 0; i < tlen; i++) {
                            char c = tval[i];
                            if (c == '"') gs_bld_append(out_result, (const uint8_t *)"\\\"", 2);
                            else if (c == '\\') gs_bld_append(out_result, (const uint8_t *)"\\\\", 2);
                            else if (c == '\n') gs_bld_append(out_result, (const uint8_t *)"\\n", 2);
                            else if (c == '\r') gs_bld_append(out_result, (const uint8_t *)"\\r", 2);
                            else if (c == '\t') gs_bld_append(out_result, (const uint8_t *)"\\t", 2);
                            else gs_bld_append(out_result, (const uint8_t *)&c, 1);
                        }
                    }
                    gs_bld_append(out_result, (const uint8_t *)"\"", 1);
                }
            }
            gs_bld_append(out_result, (const uint8_t *)"}", 1);
            row_count++;
        }
        gs_bld_append(out_result, (const uint8_t *)"]", 1);
    } else if (fmt_mode == 2) {
        // CSV format
        // Header
        for (int col = 0; col < num_cols; col++) {
            if (col > 0) gs_bld_append(out_result, (const uint8_t *)",", 1);
            const char *col_name = sqlite3_column_name(stmt, col);
            if (col_name) gs_bld_append(out_result, (const uint8_t *)col_name, strlen(col_name));
        }
        gs_bld_append(out_result, (const uint8_t *)"\n", 1);

        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            for (int col = 0; col < num_cols; col++) {
                if (col > 0) gs_bld_append(out_result, (const uint8_t *)",", 1);
                int type = sqlite3_column_type(stmt, col);
                if (type == SQLITE_NULL) {
                    // empty
                } else if (type == SQLITE_INTEGER) {
                    sqlite3_int64 ival = sqlite3_column_int64(stmt, col);
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%lld", (long long)ival);
                    gs_bld_append(out_result, (const uint8_t *)buf, strlen(buf));
                } else if (type == SQLITE_FLOAT) {
                    double fval = sqlite3_column_double(stmt, col);
                    char buf[64];
                    snprintf(buf, sizeof(buf), "%g", fval);
                    gs_bld_append(out_result, (const uint8_t *)buf, strlen(buf));
                } else {
                    const char *tval = (const char *)sqlite3_column_text(stmt, col);
                    int tlen = sqlite3_column_bytes(stmt, col);
                    gs_bld_append(out_result, (const uint8_t *)"\"", 1);
                    if (tval && tlen > 0) {
                        for (int i = 0; i < tlen; i++) {
                            char c = tval[i];
                            if (c == '"') gs_bld_append(out_result, (const uint8_t *)"\"\"", 2);
                            else gs_bld_append(out_result, (const uint8_t *)&c, 1);
                        }
                    }
                    gs_bld_append(out_result, (const uint8_t *)"\"", 1);
                }
            }
            gs_bld_append(out_result, (const uint8_t *)"\n", 1);
        }
    } else {
        // ASCII Table format
        // Buffer rows in dynamic array of string cells to compute widths
        int max_cols = num_cols < 64 ? num_cols : 64;
        int col_widths[64];
        for (int c = 0; c < max_cols; c++) {
            const char *cn = sqlite3_column_name(stmt, c);
            col_widths[c] = cn ? (int)strlen(cn) : 4;
            if (col_widths[c] < 4) col_widths[c] = 4;
        }

        struct RowData {
            char *cells[64];
        };
        int cap = 128;
        int row_count = 0;
        struct RowData *rows = (struct RowData *)malloc(sizeof(struct RowData) * cap);

        while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
            if (row_count >= cap) {
                cap *= 2;
                rows = (struct RowData *)realloc(rows, sizeof(struct RowData) * cap);
            }
            for (int col = 0; col < max_cols; col++) {
                int type = sqlite3_column_type(stmt, col);
                char cell_buf[512];
                if (type == SQLITE_NULL) {
                    snprintf(cell_buf, sizeof(cell_buf), "NULL");
                } else if (type == SQLITE_INTEGER) {
                    snprintf(cell_buf, sizeof(cell_buf), "%lld", (long long)sqlite3_column_int64(stmt, col));
                } else if (type == SQLITE_FLOAT) {
                    snprintf(cell_buf, sizeof(cell_buf), "%g", sqlite3_column_double(stmt, col));
                } else {
                    const char *t = (const char *)sqlite3_column_text(stmt, col);
                    snprintf(cell_buf, sizeof(cell_buf), "%s", t ? t : "");
                }
                int clen = (int)strlen(cell_buf);
                if (clen > col_widths[col]) {
                    if (clen > 60) col_widths[col] = 60; // cap max col width
                    else col_widths[col] = clen;
                }
                rows[row_count].cells[col] = strdup(cell_buf);
            }
            row_count++;
        }

        // Draw top separator
        gs_bld_append(out_result, (const uint8_t *)"+", 1);
        for (int c = 0; c < max_cols; c++) {
            for (int w = 0; w < col_widths[c] + 2; w++) gs_bld_append(out_result, (const uint8_t *)"-", 1);
            gs_bld_append(out_result, (const uint8_t *)"+", 1);
        }
        gs_bld_append(out_result, (const uint8_t *)"\n", 1);

        // Draw headers
        gs_bld_append(out_result, (const uint8_t *)"|", 1);
        for (int c = 0; c < max_cols; c++) {
            const char *cn = sqlite3_column_name(stmt, c);
            char hbuf[128];
            snprintf(hbuf, sizeof(hbuf), " %-*s |", col_widths[c], cn ? cn : "");
            gs_bld_append(out_result, (const uint8_t *)hbuf, strlen(hbuf));
        }
        gs_bld_append(out_result, (const uint8_t *)"\n", 1);

        // Draw middle separator
        gs_bld_append(out_result, (const uint8_t *)"+", 1);
        for (int c = 0; c < max_cols; c++) {
            for (int w = 0; w < col_widths[c] + 2; w++) gs_bld_append(out_result, (const uint8_t *)"-", 1);
            gs_bld_append(out_result, (const uint8_t *)"+", 1);
        }
        gs_bld_append(out_result, (const uint8_t *)"\n", 1);

        // Draw rows
        for (int r = 0; r < row_count; r++) {
            gs_bld_append(out_result, (const uint8_t *)"|", 1);
            for (int c = 0; c < max_cols; c++) {
                char *cell_val = rows[r].cells[c];
                char cell_fmt[128];
                snprintf(cell_fmt, sizeof(cell_fmt), " %-*.*s |", col_widths[c], col_widths[c], cell_val ? cell_val : "");
                gs_bld_append(out_result, (const uint8_t *)cell_fmt, strlen(cell_fmt));
                if (cell_val) free(cell_val);
            }
            gs_bld_append(out_result, (const uint8_t *)"\n", 1);
        }
        if (rows) free(rows);

        // Draw bottom separator
        gs_bld_append(out_result, (const uint8_t *)"+", 1);
        for (int c = 0; c < max_cols; c++) {
            for (int w = 0; w < col_widths[c] + 2; w++) gs_bld_append(out_result, (const uint8_t *)"-", 1);
            gs_bld_append(out_result, (const uint8_t *)"+", 1);
        }
        gs_bld_append(out_result, (const uint8_t *)"\n", 1);

        char summary[64];
        snprintf(summary, sizeof(summary), "(%d row%s)", row_count, row_count == 1 ? "" : "s");
        gs_bld_append(out_result, (const uint8_t *)summary, strlen(summary));
    }

    sqlite3_finalize(stmt);
    free(csql);
    return SQLITE_OK;
}

/* ========================================================================= */
/* Cryptography Bridge Implementation                                        */
/* ========================================================================= */

#define GS_KEY_LEN 32
#define GS_NONCE_LEN 12
#define GS_TAG_LEN 16

int32_t gs_crypt_gen_key(gs_rref out_key) {
    uint8_t key[GS_KEY_LEN];
    if (RAND_bytes(key, GS_KEY_LEN) != 1) return -1;
    gs_bld_append(out_key, key, GS_KEY_LEN);
    return 0;
}

int32_t gs_crypt_encrypt(sl_u8 key, sl_u8 plaintext, gs_rref out_cipher) {
    if (key.len != GS_KEY_LEN) return -1;

    uint8_t nonce[GS_NONCE_LEN];
    if (RAND_bytes(nonce, GS_NONCE_LEN) != 1) return -1;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1 ||
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GS_NONCE_LEN, NULL) != 1 ||
        EVP_EncryptInit_ex(ctx, NULL, NULL, key.data, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    uint8_t *enc_buf = NULL;
    int outlen = 0;
    if (plaintext.len > 0) {
        enc_buf = (uint8_t *)malloc((size_t)plaintext.len + 16);
        if (!enc_buf || EVP_EncryptUpdate(ctx, enc_buf, &outlen, plaintext.data, (int)plaintext.len) != 1) {
            if (enc_buf) free(enc_buf);
            EVP_CIPHER_CTX_free(ctx);
            return -1;
        }
    }

    int final_len = 0;
    uint8_t final_buf[16];
    if (EVP_EncryptFinal_ex(ctx, final_buf, &final_len) != 1) {
        if (enc_buf) free(enc_buf);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    uint8_t tag[GS_TAG_LEN];
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, GS_TAG_LEN, tag) != 1) {
        if (enc_buf) free(enc_buf);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    EVP_CIPHER_CTX_free(ctx);

    // Append Nonce (12 bytes)
    gs_bld_append(out_cipher, nonce, GS_NONCE_LEN);
    // Append Ciphertext
    if (enc_buf && outlen > 0) {
        gs_bld_append(out_cipher, enc_buf, (size_t)outlen);
        free(enc_buf);
    }
    // Append Tag (16 bytes)
    gs_bld_append(out_cipher, tag, GS_TAG_LEN);

    return 0;
}

int32_t gs_crypt_decrypt(sl_u8 key, sl_u8 ciphertext, gs_rref out_plain) {
    if (key.len != GS_KEY_LEN || ciphertext.len < GS_NONCE_LEN + GS_TAG_LEN) return -1;

    const uint8_t *nonce = ciphertext.data;
    int64_t payload_len = ciphertext.len - GS_NONCE_LEN - GS_TAG_LEN;
    const uint8_t *encrypted_data = ciphertext.data + GS_NONCE_LEN;
    const uint8_t *tag = ciphertext.data + ciphertext.len - GS_TAG_LEN;

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) return -1;

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1 ||
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, GS_NONCE_LEN, NULL) != 1 ||
        EVP_DecryptInit_ex(ctx, NULL, NULL, key.data, nonce) != 1) {
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    uint8_t *plain_buf = NULL;
    int outlen = 0;
    if (payload_len > 0) {
        plain_buf = (uint8_t *)malloc((size_t)payload_len + 16);
        if (!plain_buf || EVP_DecryptUpdate(ctx, plain_buf, &outlen, encrypted_data, (int)payload_len) != 1) {
            if (plain_buf) free(plain_buf);
            EVP_CIPHER_CTX_free(ctx);
            return -1;
        }
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, GS_TAG_LEN, (void *)tag) != 1) {
        if (plain_buf) free(plain_buf);
        EVP_CIPHER_CTX_free(ctx);
        return -1;
    }

    int final_len = 0;
    uint8_t final_buf[16];
    if (EVP_DecryptFinal_ex(ctx, final_buf, &final_len) <= 0) {
        if (plain_buf) free(plain_buf);
        EVP_CIPHER_CTX_free(ctx);
        return -1; // Auth check failed
    }

    EVP_CIPHER_CTX_free(ctx);

    if (plain_buf && outlen > 0) {
        gs_bld_append(out_plain, plain_buf, (size_t)outlen);
        free(plain_buf);
    }

    return 0;
}

int32_t gs_crypt_sha256(sl_u8 data, gs_rref out_hash_hex) {
    uint8_t hash[32];
    unsigned int hash_len = 0;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) return -1;
    if (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) != 1) {
        EVP_MD_CTX_free(ctx);
        return -1;
    }
    if (data.len > 0 && data.data) {
        if (EVP_DigestUpdate(ctx, data.data, (size_t)data.len) != 1) {
            EVP_MD_CTX_free(ctx);
            return -1;
        }
    }
    if (EVP_DigestFinal_ex(ctx, hash, &hash_len) != 1) {
        EVP_MD_CTX_free(ctx);
        return -1;
    }
    EVP_MD_CTX_free(ctx);

    char hex[65];
    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    gs_bld_append(out_hash_hex, (const uint8_t *)hex, 64);
    return 0;
}

static const char b32_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

int32_t gs_crypt_base32(sl_u8 data, gs_rref out_b32) {
    if (data.len <= 0 || !data.data) return -1;
    int64_t i = 0;
    char chunk[9];
    while (i < data.len) {
        uint64_t buf = 0;
        int count = 0;
        for (int b = 0; b < 5; b++) {
            buf <<= 8;
            if (i + b < data.len) {
                buf |= (data.data[i + b] & 0xFF);
                count++;
            }
        }
        int bits = count * 8;
        int pad = (5 - count);
        buf <<= (pad * 8);

        for (int s = 0; s < 8; s++) {
            if (s * 5 < bits) {
                int shift = 35 - s * 5;
                int idx = (int)((buf >> shift) & 0x1F);
                chunk[s] = b32_chars[idx];
            } else {
                chunk[s] = '=';
            }
        }
        chunk[8] = '\0';
        gs_bld_append(out_b32, (const uint8_t *)chunk, 8);
        i += 5;
    }
    return 0;
}

/* ========================================================================= */
/* Socket Networking Bridge Implementation                                   */
/* ========================================================================= */

int32_t gs_sock_listen_tcp(int32_t port, int32_t *out_actual_port, int32_t *out_server_fd) {
    if (!out_actual_port || !out_server_fd) return -1;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    if (listen(fd, 128) < 0) {
        close(fd);
        return -1;
    }

    socklen_t len = sizeof(addr);
    if (getsockname(fd, (struct sockaddr *)&addr, &len) == 0) {
        *out_actual_port = ntohs(addr.sin_port);
    } else {
        *out_actual_port = port;
    }

    *out_server_fd = fd;
    return 0;
}

int32_t gs_sock_accept_tcp(int32_t server_fd, int32_t timeout_ms, int32_t *out_client_fd, gs_rref out_peer_ip, int32_t *out_peer_port) {
    if (server_fd < 0 || !out_client_fd) return -1;

    struct pollfd pfd;
    pfd.fd = server_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret < 0) return -1;
    if (ret == 0) return 0;

    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addr_len);
    if (client_fd < 0) return -1;

    int opt = 1;
    setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));

    char ip_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &client_addr.sin_addr, ip_str, sizeof(ip_str));
    gs_bld_append(out_peer_ip, (const uint8_t *)ip_str, strlen(ip_str));

    if (out_peer_port) {
        *out_peer_port = ntohs(client_addr.sin_port);
    }

    *out_client_fd = client_fd;
    return 1;
}

int32_t gs_sock_connect_tcp(sl_u8 host, int32_t port, int32_t timeout_ms, int32_t *out_fd) {
    if (port <= 0 || !out_fd) return -1;
    char *chost = sl_to_cstr(host);
    if (!chost) return -1;

    struct addrinfo hints, *res = NULL, *p = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    if (getaddrinfo(chost, port_str, &hints, &res) != 0) {
        free(chost);
        return -1;
    }
    free(chost);

    int fd = -1;
    for (p = res; p != NULL; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) continue;

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        int rc = connect(fd, p->ai_addr, p->ai_addrlen);
        if (rc < 0 && errno == EINPROGRESS) {
            struct pollfd pfd;
            pfd.fd = fd;
            pfd.events = POLLOUT;
            pfd.revents = 0;
            int pret = poll(&pfd, 1, timeout_ms > 0 ? timeout_ms : 5000);
            if (pret > 0) {
                int err = 0;
                socklen_t errlen = sizeof(err);
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &errlen);
                if (err == 0) {
                    fcntl(fd, F_SETFL, flags);
                    int opt = 1;
                    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));
                    break;
                }
            }
        } else if (rc == 0) {
            fcntl(fd, F_SETFL, flags);
            int opt = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));
            break;
        }

        close(fd);
        fd = -1;
    }

    freeaddrinfo(res);

    if (fd < 0) return -1;
    *out_fd = fd;
    return 0;
}

void gs_sock_close(int32_t fd) {
    if (fd >= 0) close(fd);
}

int32_t gs_sock_send_framed(int32_t fd, sl_u8 data) {
    if (fd < 0 || (data.len > 0 && !data.data)) return -1;

    uint32_t net_len = htonl((uint32_t)data.len);
    int64_t total = 4 + data.len;
    uint8_t *buf = (uint8_t *)malloc((size_t)total);
    if (!buf) return -1;

    memcpy(buf, &net_len, 4);
    if (data.len > 0) {
        memcpy(buf + 4, data.data, (size_t)data.len);
    }

    int64_t sent = 0;
    while (sent < total) {
        ssize_t n = send(fd, buf + sent, (size_t)(total - sent), MSG_NOSIGNAL);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            free(buf);
            return -1;
        }
        sent += n;
    }

    free(buf);
    return 0;
}

int32_t gs_sock_recv_framed(int32_t fd, int32_t timeout_ms, gs_rref out_data) {
    if (fd < 0) return -1;

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return ret;

    uint32_t net_len = 0;
    int received = 0;
    while (received < 4) {
        ssize_t n = recv(fd, ((uint8_t *)&net_len) + received, 4 - received, 0);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            return -1;
        }
        received += n;
    }

    uint32_t payload_len = ntohl(net_len);
    if (payload_len > 16 * 1024 * 1024) return -1;

    uint8_t *buf = (uint8_t *)malloc(payload_len + 1);
    if (!buf) return -1;

    uint32_t got = 0;
    while (got < payload_len) {
        ssize_t n = recv(fd, buf + got, payload_len - got, 0);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            free(buf);
            return -1;
        }
        got += n;
    }

    gs_bld_append(out_data, buf, payload_len);
    free(buf);
    return 1;
}

int32_t gs_sock_open_udp(int32_t port, int32_t *out_fd) {
    if (!out_fd) return -1;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    *out_fd = fd;
    return 0;
}

int32_t gs_sock_send_udp(int32_t fd, sl_u8 host, int32_t port, sl_u8 data) {
    if (fd < 0 || port <= 0) return -1;
    char *chost = sl_to_cstr(host);
    if (!chost) return -1;

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, chost, &addr.sin_addr);
    free(chost);

    ssize_t n = sendto(fd, data.data, (size_t)data.len, 0, (struct sockaddr *)&addr, sizeof(addr));
    return (n == (ssize_t)data.len) ? 0 : -1;
}

int32_t gs_sock_recv_udp(int32_t fd, int32_t timeout_ms, gs_rref out_data, gs_rref out_src_ip, int32_t *out_src_port) {
    if (fd < 0) return -1;

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return ret;

    uint8_t buf[4096];
    struct sockaddr_in src_addr;
    socklen_t addr_len = sizeof(src_addr);
    ssize_t n = recvfrom(fd, buf, sizeof(buf), 0, (struct sockaddr *)&src_addr, &addr_len);
    if (n < 0) return -1;

    gs_bld_append(out_data, buf, (size_t)n);

    char ip_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &src_addr.sin_addr, ip_str, sizeof(ip_str));
    gs_bld_append(out_src_ip, (const uint8_t *)ip_str, strlen(ip_str));

    if (out_src_port) {
        *out_src_port = ntohs(src_addr.sin_port);
    }

    return 1;
}

/* ========================================================================= */
/* System Utilities Implementation                                           */
/* ========================================================================= */

int64_t gs_time_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return ((int64_t)ts.tv_sec * 1000000000LL) + (int64_t)ts.tv_nsec;
}

void gs_sleep_ms(int32_t ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

/* ========================================================================= */
/* Stdio & MCP Bridge Implementation                                         */
/* ========================================================================= */

int32_t gs_stdio_readline(gs_rref out_line) {
    char *line = NULL;
    size_t cap = 0;
    ssize_t n = getline(&line, &cap, stdin);
    if (n < 0) {
        if (line) free(line);
        return feof(stdin) ? 1 : -1;
    }
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) {
        line[--n] = '\0';
    }
    if (n > 0) {
        gs_bld_append(out_line, (const uint8_t *)line, (size_t)n);
    }
    free(line);
    return 0;
}

void gs_stdio_write_stdout(sl_u8 data) {
    if (data.len > 0 && data.data) {
        fwrite(data.data, 1, (size_t)data.len, stdout);
    }
    fputc('\n', stdout);
    fflush(stdout);
}

void gs_stdio_write_stderr(sl_u8 data) {
    if (data.len > 0 && data.data) {
        fwrite(data.data, 1, (size_t)data.len, stderr);
    }
    fputc('\n', stderr);
    fflush(stderr);
}
