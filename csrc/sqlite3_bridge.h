#ifndef SQLITE3_BRIDGE_H
#define SQLITE3_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *key;
    char *metadata;
    uint8_t *data;
    int64_t data_len;
} gs_sqlite_record_t;

int gs_sqlite_open(const char *path, int enable_wal, void **out_db);
int gs_sqlite_close(void *db);
int gs_sqlite_exec(void *db, const char *sql);
int gs_sqlite_put(void *db, const char *key, const char *meta, const uint8_t *data, int64_t data_len);
int gs_sqlite_get(void *db, const char *key, gs_sqlite_record_t *out_rec);
int gs_sqlite_delete(void *db, const char *key);
void gs_sqlite_free_record(gs_sqlite_record_t *rec);

int gs_sqlite_list(void *db, const char *prefix, int limit, int offset, gs_sqlite_record_t **out_recs, int *out_count);
void gs_sqlite_free_records(gs_sqlite_record_t *recs, int count);

#ifdef __cplusplus
}
#endif

#endif /* SQLITE3_BRIDGE_H */
