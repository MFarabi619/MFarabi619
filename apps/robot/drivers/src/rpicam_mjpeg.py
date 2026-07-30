# Copyright 2026 Mumtahin Farabi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


import socket

START_OF_IMAGE = b'\xff\xd8'
END_OF_IMAGE = b'\xff\xd9'
READ_CHUNK_BYTES = 65536


def frames(host, port, stream_path='', timeout_seconds=5.0):
    connection = socket.create_connection((host, port), timeout=timeout_seconds)
    connection.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if stream_path:
        connection.sendall(
            f'GET {stream_path} HTTP/1.0\r\nHost: {host}:{port}\r\n\r\n'.encode()
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
