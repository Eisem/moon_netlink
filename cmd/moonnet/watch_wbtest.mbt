///|
test "watch accepts filters and JSONL without allowing ambiguous arguments" {
  for kind in ["all", "link", "address", "route", "neighbor"] {
    guard parse_watch_args(["moonnet", "watch", kind, "--jsonl"])
      is Some(options) else {
      fail("expected watch options")
    }
    assert_eq(options.filter, kind)
    assert_true(options.jsonl)
  }
  assert_true(
    parse_watch_args(["moonnet", "watch", "--jsonl", "--jsonl"]) is None,
  )
  assert_true(parse_watch_args(["moonnet", "watch", "link", "route"]) is None)
  assert_true(parse_watch_args(["moonnet", "watch", "--json"]) is None)
}
