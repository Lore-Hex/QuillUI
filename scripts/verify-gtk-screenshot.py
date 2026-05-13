#!/usr/bin/env python3
"""Compatibility entry point for the backend-neutral screenshot verifier."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> None:
    verifier = Path(__file__).resolve().with_name("verify-backend-screenshot.py")
    os.execv(sys.executable, [sys.executable, str(verifier), *sys.argv[1:]])


if __name__ == "__main__":
    main()
