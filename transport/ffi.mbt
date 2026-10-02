///|
priv type NativeSocket

///|
extern "C" fn native_open_route_socket(groups : UInt) -> NativeSocket = "moonnetlink_open_route_socket"

///|
#borrow(self)
extern "C" fn NativeSocket::open_error(self : NativeSocket) -> Int = "moonnetlink_route_socket_open_error"

///|
#borrow(self)
extern "C" fn NativeSocket::take_fd(self : NativeSocket) -> @types.Fd = "moonnetlink_route_socket_take_fd"
