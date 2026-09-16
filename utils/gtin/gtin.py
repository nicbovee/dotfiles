#!/usr/bin/env python3
"""Generate random GTIN numbers with valid GS1 check digits."""

import argparse
import random

VALID_LENGTHS = (8, 12, 13, 14)


def check_digit(digits: str) -> int:
    """Compute the GS1 check digit for the given digit string (without check digit)."""
    # Weights alternate 3,1,3,... starting from the rightmost digit.
    total = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(digits)))
    return (10 - total % 10) % 10


def generate_gtin(length: int) -> str:
    if length not in VALID_LENGTHS:
        raise ValueError(f"GTIN length must be one of {VALID_LENGTHS}")
    body = "".join(random.choices("0123456789", k=length - 1))
    return body + str(check_digit(body))


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate random GTIN numbers.")
    parser.add_argument(
        "-l", "--length", type=int, choices=VALID_LENGTHS, default=8,
        help="GTIN length: 8, 12 (UPC-A), 13 (EAN-13), or 14 (default: 13)",
    )
    parser.add_argument(
        "-n", "--count", type=int, default=1,
        help="number of GTINs to generate (default: 1)",
    )
    args = parser.parse_args()

    for _ in range(args.count):
        print(generate_gtin(args.length))


if __name__ == "__main__":
    main()
