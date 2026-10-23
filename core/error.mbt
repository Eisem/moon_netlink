///|
/// Errors produced while decoding or encoding Netlink wire data.
#warnings("-implicit_impl_as_method")
pub(all) suberror CodecError {
  InvalidOffset(context~ : String, offset~ : Int32)
  Truncated(
    context~ : String,
    offset~ : Int32,
    needed~ : Int32,
    available~ : Int32
  )
  InvalidLength(context~ : String, length~ : UInt32, minimum~ : Int32)
  LengthTooLarge(context~ : String, length~ : UInt32)
  LengthExceedsLimit(context~ : String, length~ : Int32, maximum~ : Int32)
  InvalidAttributeType(attribute_type~ : UInt16)
  UnexpectedFieldLength(context~ : String, length~ : Int32, expected~ : Int32)
  InvalidString(context~ : String)
} derive(Debug, Eq)

///|
pub extend CodecError with Debug::{to_repr}

///|
pub extend CodecError with Eq::{equal, not_equal}
