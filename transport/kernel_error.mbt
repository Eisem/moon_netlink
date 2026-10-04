///|
fn reject_kernel_message(
  message : @core.NetlinkMessage,
  errno : Int,
) -> Unit raise {
  if @core.decode_extended_ack(message) is Some(extack) {
    let original_header = match @core.decode_control(message) {
      Some(KernelError(_, header)) | Some(Ack(header)) => Some(header)
      _ => None
    }
    raise TransportError::KernelRejectedDetailed(
      errno~,
      original_header~,
      extack~,
    )
  }
  raise TransportError::KernelRejected(errno~)
}
