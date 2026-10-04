///|
/// Invalid input supplied while building a typed Link query.
#warnings("-implicit_impl_as_method")
pub(all) suberror LinkQueryError {
  InvalidInterfaceIndex(index~ : Int)
  EmptyInterfaceName
  InterfaceNameContainsNul
  InterfaceNameInvalidUtf16
  InterfaceNameTooLong(encoded_length~ : Int, maximum~ : Int)
} derive(Debug, Eq)

///|
pub extend LinkQueryError with Debug::{to_repr}

///|
pub extend LinkQueryError with Eq::{equal, not_equal}

///|
/// Invalid textual network address. The original input is retained so callers
/// can report which configuration value failed validation.
#warnings("-implicit_impl_as_method")
pub(all) suberror AddressParseError {
  InvalidIpv4(input~ : String)
  InvalidIpv6(input~ : String)
  InvalidMac(input~ : String)
} derive(Debug, Eq)

///|
pub extend AddressParseError with Debug::{to_repr}

///|
pub extend AddressParseError with Eq::{equal, not_equal}
