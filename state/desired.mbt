///|
pub(all) enum Ensure {
  Present
  Absent
} derive(Debug, Eq)

///|
pub extend Ensure with Debug::{to_repr}

///|
pub extend Ensure with Eq::{equal, not_equal}

///|
pub(all) struct DesiredLink {
  name : String
  ensure : Ensure
  up : Bool?
  mtu : UInt?
} derive(Debug, Eq)

///|
pub extend DesiredLink with Debug::{to_repr}

///|
pub extend DesiredLink with Eq::{equal, not_equal}

///|
pub(all) struct DesiredAddress {
  interface : String
  ensure : Ensure
  address : @route.IpAddress
  prefix_length : Byte
  scope : Byte
} derive(Debug, Eq)

///|
pub extend DesiredAddress with Debug::{to_repr}

///|
pub extend DesiredAddress with Eq::{equal, not_equal}

///|
pub(all) struct DesiredRoute {
  interface : String
  ensure : Ensure
  destination : @route.IpAddress
  prefix_length : Byte
  gateway : @route.IpAddress?
  table : UInt
  priority : UInt
  protocol : Byte
  scope : Byte
} derive(Debug, Eq)

///|
pub extend DesiredRoute with Debug::{to_repr}

///|
pub extend DesiredRoute with Eq::{equal, not_equal}

///|
/// Explicit resource intent. Omitted collections and resources remain unmanaged.
pub(all) struct DesiredState {
  links : Array[DesiredLink]
  addresses : Array[DesiredAddress]
  routes : Array[DesiredRoute]
} derive(Debug, Eq)

///|
pub extend DesiredState with Debug::{to_repr}

///|
pub extend DesiredState with Eq::{equal, not_equal}

///|
pub(all) suberror StateError {
  InvalidField(path~ : String, reason~ : String)
  ConflictingIntent(identity~ : String)
  MissingInterface(name~ : String)
  UnsupportedIntent(reason~ : String)
  UnsupportedCurrentResource(identity~ : String)
} derive(Debug, Eq)

///|
pub extend StateError with Debug::{to_repr}

///|
pub extend StateError with Eq::{equal, not_equal}

///|
fn object_fields(
  value : Json,
  allowed : ArrayView[String],
  path : String,
) -> Map[String, Json] raise StateError {
  guard value is Object(fields) else {
    raise InvalidField(path~, reason="expected object")
  }
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise InvalidField(path=path + "." + key, reason="unknown field")
    }
  }
  fields
}

///|
fn field_string(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise StateError {
  guard fields.get(key) is Some(String(value)) else {
    raise InvalidField(path=path + "." + key, reason="required string")
  }
  value
}

///|
fn field_uint(
  fields : Map[String, Json],
  key : String,
  maximum : Double,
  path : String,
) -> UInt? raise StateError {
  match fields.get(key) {
    None => None
    Some(Number(value, ..)) if value >= 0 &&
      value <= maximum &&
      value.floor() == value => Some(value.to_uint())
    _ =>
      raise InvalidField(
        path=path + "." + key,
        reason="expected nonnegative integer within range",
      )
  }
}

///|
fn field_bool(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Bool? raise StateError {
  match fields.get(key) {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => raise InvalidField(path=path + "." + key, reason="expected boolean")
  }
}

///|
fn resource_array(
  fields : Map[String, Json],
  key : String,
) -> Array[Json] raise StateError {
  match fields.get(key) {
    None => []
    Some(Array(values)) if values.length() <= 1024 => values
    _ =>
      raise InvalidField(
        path=key,
        reason="expected array of at most 1024 resources",
      )
  }
}

///|
fn ensure_field(
  fields : Map[String, Json],
  path : String,
) -> Ensure raise StateError {
  match field_string(fields, "ensure", path) {
    "present" => Present
    "absent" => Absent
    _ =>
      raise InvalidField(
        path=path + ".ensure",
        reason="expected present or absent",
      )
  }
}

///|
pub fn address_identity(address : DesiredAddress) -> String {
  "\{address.interface}|\{address.address.to_string()}/\{address.prefix_length.to_int()}"
}

///|
pub fn route_identity(route : DesiredRoute) -> String {
  "\{route.interface}|\{route.table}|\{route.destination.to_string()}/\{route.prefix_length.to_int()}|\{Repr(route.gateway)}|\{route.priority}"
}

///|
/// Validate typed callers too; duplicate identities are rejected even if equal.
pub fn validate_desired(desired : DesiredState) -> Unit raise {
  let identities : Map[String, Bool] = Map([])
  let check_unique = fn(key : String) raise {
    if identities.contains(key) {
      raise StateError::ConflictingIntent(identity=key)
    }
    identities[key] = true
  }
  for link in desired.links {
    ignore(@route.encode_get_link_by_name(1, link.name))
    if link.mtu is Some(mtu) {
      ignore(@route.encode_set_link_mtu(1, 1, mtu))
    }
    check_unique("link|" + link.name)
  }
  for address in desired.addresses {
    ignore(@route.encode_get_link_by_name(1, address.interface))
    ignore(
      @route.encode_add_address(1, {
        interface_index: 1,
        address: address.address,
        prefix_length: address.prefix_length,
        scope: address.scope,
      }),
    )
    check_unique("address|" + address_identity(address))
  }
  for route in desired.routes {
    ignore(@route.encode_get_link_by_name(1, route.interface))
    ignore(
      @route.encode_add_route(1, {
        destination: route.destination,
        prefix_length: route.prefix_length,
        gateway: route.gateway,
        output_interface: 1,
        table: route.table,
        priority: Some(route.priority),
        protocol: route.protocol,
        scope: route.scope,
      }),
    )
    check_unique("route|" + route_identity(route))
  }
}

///|
/// Parse schema version 1. JSON syntax/IP errors retain their original types.
/// A one-Mi-code-unit and 64-level limit bounds untrusted configuration parsing.

///|
#warnings("-deprecated")
fn parse_config_json(text : String) -> Json raise @json.ParseError {
  // The current core marks this limit parameter deprecated, but it is the
  // available API for bounding an untrusted configuration below its default.
  @json.parse(text, max_nesting_depth=64)
}

///|
pub fn DesiredState::parse(text : String) -> DesiredState raise {
  if text.length() > 1024 * 1024 {
    raise StateError::InvalidField(
      path="root",
      reason="configuration too large",
    )
  }
  let root = object_fields(
    parse_config_json(text),
    ["schema_version", "links", "addresses", "routes"],
    "root",
  )
  if field_uint(root, "schema_version", 1.0, "root") != Some(1) {
    raise StateError::InvalidField(
      path="schema_version",
      reason="required version 1",
    )
  }
  let links = [
    for index, value in resource_array(root, "links") => {
      let path = "links[\{index}]"
      let fields = object_fields(value, ["name", "ensure", "up", "mtu"], path)
      {
        name: field_string(fields, "name", path),
        ensure: ensure_field(fields, path),
        up: field_bool(fields, "up", path),
        mtu: field_uint(fields, "mtu", 4294967295.0, path),
      }
    }
  ]
  let addresses = [
    for index, value in resource_array(root, "addresses") => {
      let path = "addresses[\{index}]"
      let fields = object_fields(
        value,
        ["interface", "ensure", "address", "prefix_length", "scope"],
        path,
      )
      guard field_uint(fields, "prefix_length", 128.0, path) is Some(prefix) else {
        raise StateError::InvalidField(
          path=path + ".prefix_length",
          reason="required integer",
        )
      }
      {
        interface: field_string(fields, "interface", path),
        ensure: ensure_field(fields, path),
        address: @route.IpAddress::parse(field_string(fields, "address", path)),
        prefix_length: prefix.to_byte(),
        scope: field_uint(fields, "scope", 255.0, path).unwrap_or(0).to_byte(),
      }
    }
  ]
  let routes = [
    for index, value in resource_array(root, "routes") => {
      let path = "routes[\{index}]"
      let fields = object_fields(
        value,
        [
          "interface", "ensure", "destination", "prefix_length", "gateway", "table",
          "priority", "protocol", "scope",
        ],
        path,
      )
      let destination = @route.IpAddress::parse(
        field_string(fields, "destination", path),
      )
      let gateway = match fields.get("gateway") {
        None => None
        Some(String(ip)) => Some(@route.IpAddress::parse(ip))
        _ =>
          raise StateError::InvalidField(
            path=path + ".gateway",
            reason="omit or use IP string",
          )
      }
      guard field_uint(fields, "prefix_length", 128.0, path) is Some(prefix) else {
        raise StateError::InvalidField(
          path=path + ".prefix_length",
          reason="required integer",
        )
      }
      let metric = field_uint(fields, "priority", 4294967295.0, path).unwrap_or(
        0,
      )
      let priority : UInt = match destination {
        V6(_) if metric == 0 => 1024
        _ => metric
      }
      {
        interface: field_string(fields, "interface", path),
        ensure: ensure_field(fields, path),
        destination,
        prefix_length: prefix.to_byte(),
        gateway,
        table: field_uint(fields, "table", 4294967295.0, path).unwrap_or(254),
        priority,
        protocol: field_uint(fields, "protocol", 255.0, path)
        .unwrap_or(4)
        .to_byte(),
        scope: field_uint(fields, "scope", 255.0, path)
        .unwrap_or(
          match destination {
            V4(_) if gateway is None => 253
            _ => 0
          },
        )
        .to_byte(),
      }
    }
  ]
  let desired : DesiredState = { links, addresses, routes, }
  validate_desired(desired)
  desired
}
