import socket

START_OF_IMAGE = b"\xff\xd8"
END_OF_IMAGE = b"\xff\xd9"
READ_CHUNK_BYTES = 65536


def frames(host, port, stream_path="", timeout_seconds=5.0):
    connection = socket.create_connection((host, port), timeout=timeout_seconds)
    connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if stream_path:
        connection.sendall(
            f"GET {stream_path} HTTP/1.0\r\nHost: {host}:{port}\r\n\r\n".encode()
        )
    try:
        buffer = bytearray()
        while True:
            chunk = connection.recv(READ_CHUNK_BYTES)
            if not chunk:
                return
            buffer.extend(chunk)
            yield from take_frames(buffer)
    finally:
        connection.close()


def take_frames(buffer):
    while True:
        start = buffer.find(START_OF_IMAGE)
        if start < 0:
            break
        end = buffer.find(END_OF_IMAGE, start + 2)
        if end < 0:
            break
        end += 2
        frame = bytes(buffer[start:end])
        del buffer[:end]
        yield frame
