use embassy_net::tcp::TcpSocket;

pub async fn read_exact(
    socket: &mut TcpSocket<'_>,
    buf: &mut [u8],
) -> Result<(), embassy_net::tcp::Error> {
    let mut offset = 0;
    while offset < buf.len() {
        match socket.read(&mut buf[offset..]).await {
            Ok(0) => return Err(embassy_net::tcp::Error::ConnectionReset),
            Ok(bytes_read) => {
                offset += bytes_read;
            }
            Err(error) => return Err(error),
        }
    }

    Ok(())
}

pub async fn write_all(
    socket: &mut TcpSocket<'_>,
    payload: &[u8],
) -> Result<(), embassy_net::tcp::Error> {
    let mut bytes_written_total = 0;

    while bytes_written_total < payload.len() {
        let bytes_written_this_iteration = socket.write(&payload[bytes_written_total..]).await?;
        if bytes_written_this_iteration == 0 {
            return Err(embassy_net::tcp::Error::ConnectionReset);
        }

        bytes_written_total += bytes_written_this_iteration;
    }

    Ok(())
}
