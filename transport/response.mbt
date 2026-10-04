///|
let nlm_f_multi : UInt16 = 0x0002

///|
let nlm_f_dump_intr : UInt16 = 0x0010

///|
// Keep interruption state across datagrams and drain through DONE before
// reporting failure, so the socket can accept the next serialized request.
priv struct DumpResponse {
  sequence : UInt
  messages : Array[@core.NetlinkMessage]
  mut interrupted : Bool
}

///|
fn DumpResponse::new(sequence : UInt) -> DumpResponse {
  { sequence, messages: [], interrupted: false, }
}

///|
fn DumpResponse::consume(
  self : DumpResponse,
  datagram : ArrayView[@core.NetlinkMessage],
) -> Bool raise {
  let mut complete = false
  for message in datagram {
    if message.header.sequence != self.sequence {
      continue
    }
    if complete {
      raise TransportError::UnexpectedControl(
        message_type=message.header.message_type,
      )
    }
    if (message.header.flags & nlm_f_dump_intr) != 0 {
      self.interrupted = true
    }
    match @core.decode_control(message) {
      Some(Done(None | Some(0))) => complete = true
      Some(Done(Some(errno))) =>
        reject_kernel_message(message, if errno < 0 { -errno } else { errno })
      Some(Ack(_)) | Some(Noop) => ()
      Some(KernelError(errno, _)) => reject_kernel_message(message, errno)
      Some(Overrun) =>
        raise TransportError::UnexpectedControl(
          message_type=message.header.message_type,
        )
      None => self.messages.push(message)
    }
  }
  if complete && self.interrupted {
    raise TransportError::DumpInterrupted(sequence=self.sequence)
  }
  complete
}

///|
fn decode_single_reply(
  messages : ArrayView[@core.NetlinkMessage],
  sequence : UInt,
  response_type : UInt16,
) -> @core.NetlinkMessage? raise {
  let mut reply : @core.NetlinkMessage? = None
  for message in messages {
    if message.header.sequence != sequence {
      continue
    }
    if (message.header.flags & nlm_f_dump_intr) != 0 {
      raise TransportError::DumpInterrupted(sequence~)
    }
    match @core.decode_control(message) {
      Some(Ack(_)) | Some(Noop) => ()
      Some(KernelError(errno, _)) => reject_kernel_message(message, errno)
      None if message.header.message_type == response_type &&
        (message.header.flags & nlm_f_multi) == 0 &&
        reply is None => reply = Some(message)
      _ =>
        raise TransportError::UnexpectedControl(
          message_type=message.header.message_type,
        )
    }
  }
  reply
}
