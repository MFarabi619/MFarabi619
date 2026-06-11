from west.commands import WestCommand


class Lazyzephyr(WestCommand):
    def __init__(self):
        super().__init__(
            name="lazyzephyr",
            help="echo lazyzephyr",
            description="Placeholder command — prints 'lazyzephyr' and exits.",
        )

    def do_add_parser(self, parser_adder):
        return parser_adder.add_parser(self.name, help=self.help, description=self.description)

    def do_run(self, args, unknown_args):
        self.inf("lazyzephyr")
