#include "moonbit.h"

#include <errno.h>
#include <stdint.h>

#ifdef __linux__
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

typedef struct {
  int fd;
  int open_error;
} moonnetlink_route_socket;

static void moonnetlink_route_socket_finalize(void *self) {
  moonnetlink_route_socket *socket = (moonnetlink_route_socket *)self;
#ifdef __linux__
  if (socket->fd >= 0) {
    close(socket->fd);
    socket->fd = -1;
  }
#else
  (void)socket;
#endif
}

MOONBIT_FFI_EXPORT moonnetlink_route_socket *
moonnetlink_open_route_socket(uint32_t groups) {
  moonnetlink_route_socket *result = moonbit_make_external_object(
      moonnetlink_route_socket_finalize, sizeof(moonnetlink_route_socket));
  result->fd = -1;
  result->open_error = 0;
#ifdef __linux__
  int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_NONBLOCK | SOCK_CLOEXEC,
                  NETLINK_ROUTE);
  if (fd < 0) {
    result->open_error = errno;
    return result;
  }

  struct sockaddr_nl local = {0};
  local.nl_family = AF_NETLINK;
  local.nl_pid = 0;
  local.nl_groups = groups;
  if (bind(fd, (struct sockaddr *)&local, sizeof(local)) < 0) {
    int saved_errno = errno;
    close(fd);
    result->open_error = saved_errno;
    return result;
  }

  struct sockaddr_nl kernel = {0};
  kernel.nl_family = AF_NETLINK;
  kernel.nl_pid = 0;
  kernel.nl_groups = 0;
  if (connect(fd, (struct sockaddr *)&kernel, sizeof(kernel)) < 0) {
    int saved_errno = errno;
    close(fd);
    result->open_error = saved_errno;
    return result;
  }

  int enabled = 1;
#ifdef NETLINK_EXT_ACK
  (void)setsockopt(fd, SOL_NETLINK, NETLINK_EXT_ACK, &enabled,
                   sizeof(enabled));
#endif
#ifdef NETLINK_GET_STRICT_CHK
  (void)setsockopt(fd, SOL_NETLINK, NETLINK_GET_STRICT_CHK, &enabled,
                   sizeof(enabled));
#endif
  result->fd = fd;
#else
  (void)groups;
  result->open_error = 38; /* ENOSYS */
#endif
  return result;
}

MOONBIT_FFI_EXPORT int32_t
moonnetlink_route_socket_open_error(moonnetlink_route_socket *socket) {
  return socket->open_error;
}

#ifdef _WIN32
MOONBIT_FFI_EXPORT void *
moonnetlink_route_socket_take_fd(moonnetlink_route_socket *socket) {
  (void)socket;
  return NULL;
}
#else
MOONBIT_FFI_EXPORT int32_t
moonnetlink_route_socket_take_fd(moonnetlink_route_socket *socket) {
  int fd = socket->fd;
  socket->fd = -1;
  return fd;
}
#endif
