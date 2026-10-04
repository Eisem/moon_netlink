///|
test "kernel rejection retains errno original header and extack diagnostics" {
  let text = @core.encode_attribute({
    attribute_type: 1,
    nested: false,
    network_byte_order: false,
    payload: b"invalid gateway\x00",
  })
  let payload = b"\xea\xff\xff\xff\x20\x00\x00\x00\x18\x00\x05\x06\x07\x00\x00\x00\x00\x00\x00\x00".to_array()
  for byte in text {
    payload.push(byte)
  }
  let message = response_message(
    @core.nlmsg_error,
    flags=0x300,
    payload=Bytes::from_array(payload[:]),
  )
  try reject_kernel_message(message, 22) catch {
    KernelRejectedDetailed(errno~, original_header~, extack~) => {
      assert_eq(errno, 22)
      assert_eq(original_header.unwrap().message_type, @route.rtm_newroute)
      assert_eq(extack.message, Some("invalid gateway"))
    }
    err => fail("unexpected kernel error: \{Repr(err)}")
  } noraise {
    _ => fail("kernel rejection accepted")
  }
  let done_payload = [ for byte in b"\xea\xff\xff\xff" => byte ]
  for byte in text {
    done_payload.push(byte)
  }
  try
    DumpResponse::new(7).consume([
      response_message(
        @core.nlmsg_done,
        flags=0x200,
        payload=Bytes::from_array(done_payload[:]),
      ),
    ])
  catch {
    KernelRejectedDetailed(errno~, original_header~, extack~) => {
      assert_eq(errno, 22)
      assert_eq(original_header, None)
      assert_eq(extack.message, Some("invalid gateway"))
    }
    err => fail("unexpected DONE error: \{Repr(err)}")
  } noraise {
    _ => fail("negative DONE accepted")
  }
}

///|
fn response_message(
  message_type : UInt16,
  sequence? : UInt = 7,
  flags? : UInt16 = 0,
  payload? : Bytes = b"",
) -> @core.NetlinkMessage {
  {
    header: {
      length: (16 + payload.length()).reinterpret_as_uint(),
      message_type,
      sequence,
      flags,
      port_id: 0,
    },
    payload,
  }
}

///|
fn response_ack() -> @core.NetlinkMessage {
  response_message(
    @core.nlmsg_error,
    payload=b"\x00\x00\x00\x00\x20\x00\x00\x00\x12\x00\x01\x00\x07\x00\x00\x00\x00\x00\x00\x00",
  )
}

///|
test "dump waits past ACK and ignores unrelated sequences until DONE" {
  let response = DumpResponse::new(7)
  let body = response_message(@route.rtm_newlink, flags=2)
  assert_false(
    response.consume([
      response_message(@route.rtm_newlink, sequence=8, flags=0x12),
      response_ack(),
      body,
    ]),
  )
  assert_true(response.consume([response_message(@core.nlmsg_done)]))
  assert_eq(response.messages, [body])
}

///|
test "dump interruption on body is remembered until a later DONE" {
  let response = DumpResponse::new(7)
  assert_false(
    response.consume([response_message(@route.rtm_newlink, flags=0x12)]),
  )
  assert_false(
    response.consume([response_message(@route.rtm_newlink, flags=2)]),
  )
  try response.consume([response_message(@core.nlmsg_done)]) catch {
    DumpInterrupted(sequence~) => assert_eq(sequence, 7)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("interrupted dump must not return partial state as success")
  }
}

///|
test "dump interruption on DONE fails even when its status is zero" {
  let response = DumpResponse::new(7)
  try
    response.consume([
      response_message(@route.rtm_newlink, flags=2),
      response_message(
        @core.nlmsg_done,
        flags=0x10,
        payload=b"\x00\x00\x00\x00",
      ),
    ])
  catch {
    DumpInterrupted(sequence~) => assert_eq(sequence, 7)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("flagged DONE must not make a dump successful")
  }
}

///|
test "dump propagates a negative DONE status" {
  let response = DumpResponse::new(7)
  try
    response.consume([
      response_message(@core.nlmsg_done, payload=b"\xfc\xff\xff\xff"),
    ])
  catch {
    KernelRejected(errno~) => assert_eq(errno, 4)
    err => fail("unexpected error: \{Repr(err)}")
  } noraise {
    _ => fail("negative DONE status must fail")
  }
}

///|
test "single reply completes on data without DONE and ignores stale responses" {
  let reply = response_message(@route.rtm_newlink)
  assert_eq(
    decode_single_reply(
      [response_message(@core.nlmsg_done, sequence=8), response_ack(), reply],
      7,
      @route.rtm_newlink,
    ),
    Some(reply),
  )
  assert_eq(decode_single_reply([response_ack()], 7, @route.rtm_newlink), None)
}

///|
test "single reply rejects wrong type multipart data and DONE" {
  for
    message in [
      response_message(@route.rtm_newaddr),
      response_message(@route.rtm_newlink, flags=2),
      response_message(@core.nlmsg_done),
    ] {
    try decode_single_reply([message], 7, @route.rtm_newlink) catch {
      UnexpectedControl(message_type~) =>
        assert_eq(message_type, message.header.message_type)
      err => fail("unexpected error: \{Repr(err)}")
    } noraise {
      _ => fail("unexpected point-query response must fail")
    }
  }
}
