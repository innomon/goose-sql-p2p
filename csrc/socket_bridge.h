#ifndef SOCKET_BRIDGE_H
#define SOCKET_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int gs_net_listen_tcp(int port, int *out_actual_port, int *out_server_fd);
int gs_net_accept_tcp(int server_fd, int timeout_ms, int *out_client_fd, char *out_peer_ip, int max_ip_len, int *out_peer_port);
int gs_net_connect_tcp(const char *host, int port, int timeout_ms, int *out_fd);
void gs_net_close(int fd);

int gs_net_send_framed(int fd, const uint8_t *data, int64_t len);
int gs_net_recv_framed(int fd, int timeout_ms, uint8_t **out_data, int64_t *out_len);
void gs_net_free(void *ptr);

int gs_net_open_udp_broadcast(int port, int *out_fd);
int gs_net_sendto_udp(int fd, const char *host, int port, const uint8_t *data, int64_t len);
int gs_net_recvfrom_udp(int fd, int timeout_ms, uint8_t **out_data, int64_t *out_len, char *out_src_ip, int max_ip_len, int *out_src_port);

#ifdef __cplusplus
}
#endif

#endif /* SOCKET_BRIDGE_H */
