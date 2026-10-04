///|
test "snapshot owns collections and preserves fields including unknown attributes" {
  let links : Array[@route.Link] = [
    {
      index: 7,
      name: Some("veth0"),
      kind: Some("veth"),
      mtu: Some(1400),
      mac: None,
      flags: 1,
      operational_state: Some(Up),
      master_index: None,
      unknown_attributes: [
        {
          attribute_type: 99,
          nested: false,
          network_byte_order: false,
          payload: b"raw",
        },
      ],
    },
  ]
  let attributes = links[0].unknown_attributes
  let snapshot = @state.NetworkSnapshot::new(links~, addresses=[], routes=[], neighbors=[])
  attributes.clear()
  links.clear()
  assert_eq(snapshot.interface_name(7), Some("veth0"))
  assert_eq(snapshot.interface_name(8), None)
  let link = snapshot.link_by_name("veth0").unwrap()
  assert_eq(link.mtu, Some(1400))
  assert_eq(link.unknown_attributes.length(), 1)
  assert_eq(link.unknown_attributes[0].payload, b"raw")
  assert_eq(snapshot.link_by_name("missing"), None)
}
