#ifndef BRIDGE_H
#define BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* SQLite Bridge */
int32_t gs_db_open(sl_u8 path, uint8_t enable_wal, uint64_t *out_handle);
int32_t gs_db_close(uint64_t handle);
int32_t gs_db_exec(uint64_t handle, sl_u8 sql);
int32_t gs_db_put(uint64_t handle, sl_u8 key, sl_u8 meta, sl_u8 data);
int32_t gs_db_get(uint64_t handle, sl_u8 key, gs_rref out_meta, gs_rref out_data);
int32_t gs_db_delete(uint64_t handle, sl_u8 key);
int32_t gs_db_list(uint64_t handle, sl_u8 prefix, int32_t limit, int32_t offset, gs_rref out_json);

/* Cryptography Bridge */
int32_t gs_crypt_gen_key(gs_rref out_key);
int32_t gs_crypt_encrypt(sl_u8 key, sl_u8 plaintext, gs_rref out_cipher);
int32_t gs_crypt_decrypt(sl_u8 key, sl_u8 ciphertext, gs_rref out_plain);
int32_t gs_crypt_sha256(sl_u8 data, gs_rref out_hash_hex);
int32_t gs_crypt_base32(sl_u8 data, gs_rref out_b32);

/* Socket Networking Bridge */
int32_t gs_sock_listen_tcp(int32_t port, int32_t *out_actual_port, int32_t *out_server_fd);
int32_t gs_sock_accept_tcp(int32_t server_fd, int32_t timeout_ms, int32_t *out_client_fd, gs_rref out_peer_ip, int32_t *out_peer_port);
int32_t gs_sock_connect_tcp(sl_u8 host, int32_t port, int32_t timeout_ms, int32_t *out_fd);
void gs_sock_close(int32_t fd);
int32_t gs_sock_send_framed(int32_t fd, sl_u8 data);
int32_t gs_sock_recv_framed(int32_t fd, int32_t timeout_ms, gs_rref out_data);
int32_t gs_sock_open_udp(int32_t port, int32_t *out_fd);
int32_t gs_sock_send_udp(int32_t fd, sl_u8 host, int32_t port, sl_u8 data);
int32_t gs_sock_recv_udp(int32_t fd, int32_t timeout_ms, gs_rref out_data, gs_rref out_src_ip, int32_t *out_src_port);

/* System Utilities */
int64_t gs_time_now_ns(void);
void gs_sleep_ms(int32_t ms);

#ifdef __cplusplus
}
#endif

#include "bridge.c"

#endif /* BRIDGE_H */
