#!/usr/bin/env python3

import os

from robot_generator_common.common import BaseGenerator


class LaunchGenerator(BaseGenerator):
    def __init__(self, setup_path: str, output_path: str) -> None:
        super().__init__(setup_path)
        self.output_path = output_path
        os.makedirs(self.output_path, exist_ok=True)

    def generate(self) -> None:
        raise NotImplementedError()
