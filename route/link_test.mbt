///|
test "encode RTM_GETLINK request" {
  let request = @route.encode_get_links(42)
  assert_eq(request.length(), 32)
  assert_eq(@core.read_u32_le(request, 0), 32)
  assert_eq(@core.read_u16_le(request, 4), @route.rtm_getlink)
  assert_eq(@core.read_u16_le(request, 6), 0x0301)
  assert_eq(@core.read_u32_le(request, 8), 42)
}
