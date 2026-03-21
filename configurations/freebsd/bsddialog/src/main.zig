const doombsd = @import("doombsd");

pub fn main() !void {
    doombsd.session.set_locale();
    try doombsd.session.init();
    defer doombsd.session.end();

    try doombsd.theme.apply();
    try doombsd.loop.run();
}
