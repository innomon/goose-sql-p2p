// Socket networking and timing bridge
namespace net;

import std;

extern fn sock_listen_tcp_c(port: i32, out_actual_port: i32&, out_server_fd: i32&) -> i32 = "gs_sock_listen_tcp";
extern fn sock_accept_tcp_c(server_fd: i32, timeout_ms: i32, out_client_fd: i32&, out_peer_ip: u8[>..]&, out_peer_port: i32&) -> i32 = "gs_sock_accept_tcp";
extern fn sock_connect_tcp_c(host: const u8[:], port: i32, timeout_ms: i32, out_fd: i32&) -> i32 = "gs_sock_connect_tcp";
extern fn sock_close_c(fd: i32) = "gs_sock_close";
extern fn sock_send_framed_c(fd: i32, data: const u8[:]) -> i32 = "gs_sock_send_framed";
extern fn sock_recv_framed_c(fd: i32, timeout_ms: i32, out_data: u8[>..]&) -> i32 = "gs_sock_recv_framed";
extern fn sock_open_udp_c(port: i32, out_fd: i32&) -> i32 = "gs_sock_open_udp";
extern fn sock_send_udp_c(fd: i32, host: const u8[:], port: i32, data: const u8[:]) -> i32 = "gs_sock_send_udp";
extern fn sock_recv_udp_c(fd: i32, timeout_ms: i32, out_data: u8[>..]&, out_src_ip: u8[>..]&, out_src_port: i32&) -> i32 = "gs_sock_recv_udp";

extern fn time_now_ns_c() -> i64 = "gs_time_now_ns";
extern fn sleep_ms_c(ms: i32) = "gs_sleep_ms";

fn now_ns() -> i64 {
    return time_now_ns_c();
}

fn sleep_ms(ms: i32) {
    sleep_ms_c(ms);
}

fn listen_tcp(port: i32, out_actual_port: i32&, out_server_fd: i32&) -> bool {
    return sock_listen_tcp_c(port, out_actual_port, out_server_fd) == 0;
}

fn accept_tcp(server_fd: i32, timeout_ms: i32, out_client_fd: i32&, out_peer_ip: u8[>..]&, out_peer_port: i32&) -> bool {
    var rc = sock_accept_tcp_c(server_fd, timeout_ms, out_client_fd, out_peer_ip, out_peer_port);
    return rc > 0;
}

fn connect_tcp(host: const u8[:], port: i32, timeout_ms: i32) -> i32 {
    var fd: i32 = -1;
    var rc = sock_connect_tcp_c(host, port, timeout_ms, fd);
    if rc != 0 {
        return -1;
    }
    return fd;
}

fn close_fd(fd: i32) {
    if fd >= 0 {
        sock_close_c(fd);
    }
}

fn send_framed(fd: i32, data: const u8[:]) -> bool {
    return sock_send_framed_c(fd, data) == 0;
}

fn recv_framed(fd: i32, timeout_ms: i32, out_data: u8[>..]&) -> i32 {
    return sock_recv_framed_c(fd, timeout_ms, out_data);
}

fn open_udp(port: i32, out_fd: i32&) -> bool {
    return sock_open_udp_c(port, out_fd) == 0;
}

fn send_udp(fd: i32, host: const u8[:], port: i32, data: const u8[:]) -> bool {
    return sock_send_udp_c(fd, host, port, data) == 0;
}

fn recv_udp(fd: i32, timeout_ms: i32, out_data: u8[>..]&, out_src_ip: u8[>..]&, out_src_port: i32&) -> i32 {
    return sock_recv_udp_c(fd, timeout_ms, out_data, out_src_ip, out_src_port);
}
