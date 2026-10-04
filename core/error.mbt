///|
/// Errors produced while decoding or encoding Netlink wire data.
#warnings("-implicit_impl_as_method")
pub(all) suberror CodecError {
  InvalidOffset(context~ : String, offset~ : Int)
  Truncated(context~ : String, offset~ : Int, needed~ : Int, available~ : Int)
  InvalidLength(context~ : String, length~ : UInt, minimum~ : Int)
  LengthTooLarge(context~ : String, length~ : UInt)
  LengthExceedsLimit(context~ : String, length~ : Int, maximum~ : Int)
  InvalidAttributeType(attribute_type~ : UInt16)
  UnexpectedFieldLength(context~ : String, length~ : Int, expected~ : Int)
  InvalidString(context~ : String)
} derive(Debug, Eq)

///|
pub extend CodecError with Debug::{to_repr}

///|
pub extend CodecError with Eq::{equal, not_equal}
