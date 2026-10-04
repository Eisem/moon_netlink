///|
test "optional kernel diagnostics serialize as ordinary values or null" {
  let error = @transport.TransportError::KernelRejectedDetailed(
    errno=101,
    original_header=None,
    extack={
      message: Some("bad gateway"),
      offset: Some(20U),
      cookie: None,
      missing_type: None,
      missing_nest: None,
      unknown_attributes: [],
    },
  )
  let expected : Json = {
    "kind": "kernel",
    "errno": 101,
    "message": "bad gateway",
    "offset": 20,
  }
  assert_eq(error_json(error), expected)
  let missing = @transport.TransportError::KernelRejectedDetailed(
    errno=101,
    original_header=None,
    extack={
      message: None,
      offset: None,
      cookie: None,
      missing_type: None,
      missing_nest: None,
      unknown_attributes: [],
    },
  )
  let expected_missing : Json = {
    "kind": "kernel",
    "errno": 101,
    "message": null,
    "offset": null,
  }
  assert_eq(error_json(missing), expected_missing)
}

///|
test "stale interface diagnostic index serializes as a number or null" {
  for observed in [Some(8), None] {
    let error = @state.SafetyError::StaleInterface(
      interface="veth0",
      planned_index=7,
      observed_index=observed,
    )
    let expected : Json = {
      "kind": "stale_interface",
      "interface": "veth0",
      "planned_index": 7,
      "observed_index": if observed is Some(index) {
        @json.to_json(index)
      } else {
        Json::null()
      },
    }
    assert_eq(error_json(error), expected)
  }
}
