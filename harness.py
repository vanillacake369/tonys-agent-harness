#!/usr/bin/env python3
"""Compatibility entrypoint for the agent harness CLI."""

from agent_harness.cli import main


if __name__ == "__main__":
    raise SystemExit(main())
