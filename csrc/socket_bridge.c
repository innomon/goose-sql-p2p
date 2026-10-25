#include "socket_bridge.h"
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

int gs_net_listen_tcp(int port, int *out_actual_port, int *out_server_fd) {
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

int gs_net_accept_tcp(int server_fd, int timeout_ms, int *out_client_fd, char *out_peer_ip, int max_ip_len, int *out_peer_port) {
    if (server_fd < 0 || !out_client_fd) return -1;

    struct pollfd pfd;
    pfd.fd = server_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return ret; // 0 = timeout, <0 = error

    struct sockaddr_in client_addr;
    socklen_t addr_len = sizeof(client_addr);
    int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addr_len);
    if (client_fd < 0) return -1;

    int opt = 1;
    setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &opt, sizeof(opt));

    if (out_peer_ip && max_ip_len > 0) {
        inet_ntop(AF_INET, &client_addr.sin_addr, out_peer_ip, max_ip_len);
    }
    if (out_peer_port) {
        *out_peer_port = ntohs(client_addr.sin_port);
    }

    *out_client_fd = client_fd;
    return 1;
}

int gs_net_connect_tcp(const char *host, int port, int timeout_ms, int *out_fd) {
    if (!host || port <= 0 || !out_fd) return -1;

    struct addrinfo hints, *res = NULL, *p = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    if (getaddrinfo(host, port_str, &hints, &res) != 0) {
        return -1;
    }

    int fd = -1;
    for (p = res; p != NULL; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) continue;

        // Set non-blocking for connect timeout
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
                    // Connected successfully
                    fcntl(fd, F_SETFL, flags); // restore blocking
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

void gs_net_close(int fd) {
    if (fd >= 0) close(fd);
}

int gs_net_send_framed(int fd, const uint8_t *data, int64_t len) {
    if (fd < 0 || (!data && len > 0) || len < 0) return -1;

    uint32_t net_len = htonl((uint32_t)len);
    int64_t total = 4 + len;
    uint8_t *buf = (uint8_t *)malloc(total);
    if (!buf) return -1;

    memcpy(buf, &net_len, 4);
    if (len > 0) {
        memcpy(buf + 4, data, len);
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

int gs_net_recv_framed(int fd, int timeout_ms, uint8_t **out_data, int64_t *out_len) {
    if (fd < 0 || !out_data || !out_len) return -1;

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return ret; // 0 = timeout, <0 = error

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
    if (payload_len > 16 * 1024 * 1024) { // Sanity limit 16MB
        return -1;
    }

    uint8_t *buf = (uint8_t *)malloc(payload_len + 1);
    if (!buf) return -1;

    int64_t got = 0;
    while (got < payload_len) {
        ssize_t n = recv(fd, buf + got, (size_t)(payload_len - got), 0);
        if (n <= 0) {
            if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            free(buf);
            return -1;
        }
        got += n;
    }

    buf[payload_len] = '\0';
    *out_data = buf;
    *out_len = payload_len;
    return 1;
}

void gs_net_free(void *ptr) {
    if (ptr) free(ptr);
}

int gs_net_open_udp_broadcast(int port, int *out_fd) {
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

int gs_net_sendto_udp(int fd, const char *host, int port, const uint8_t *data, int64_t len) {
    if (fd < 0 || !host || port <= 0) return -1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    inet_pton(AF_INET, host, &addr.sin_addr);

    ssize_t n = sendto(fd, data, (size_t)len, 0, (struct sockaddr *)&addr, sizeof(addr));
    return (n == len) ? 0 : -1;
}

int gs_net_recvfrom_udp(int fd, int timeout_ms, uint8_t **out_data, int64_t *out_len, char *out_src_ip, int max_ip_len, int *out_src_port) {
    if (fd < 0 || !out_data || !out_len) return -1;

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    int ret = poll(&pfd, 1, timeout_ms);
    if (ret <= 0) return ret;

    uint8_t buf[4096];
    struct sockaddr_in src_addr;
    socklen_t addr_len = sizeof(src_addr);
    ssize_t n = recvfrom(fd, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&src_addr, &addr_len);
    if (n < 0) return -1;

    uint8_t *res = (uint8_t *)malloc(n + 1);
    if (!res) return -1;
    memcpy(res, buf, n);
    res[n] = '\0';

    if (out_src_ip && max_ip_len > 0) {
        inet_ntop(AF_INET, &src_addr.sin_addr, out_src_ip, max_ip_len);
    }
    if (out_src_port) {
        *out_src_port = ntohs(src_addr.sin_port);
    }

    *out_data = res;
    *out_len = n;
    return 1;
}
