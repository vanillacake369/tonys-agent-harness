default: test

test:
    python3 -m unittest discover -s tests -v

check: test
    python3 harness.py doctor
    nix flake check
