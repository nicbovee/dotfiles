# GTIN Generator

A simple, dependency-free Python script that generates random GTIN numbers with valid GS1 check digits.

Supports all standard GTIN lengths:

- **GTIN-8** (EAN-8)
- **GTIN-12** (UPC-A)
- **GTIN-13** (EAN-13, default)
- **GTIN-14** (ITF-14)

## Usage

```bash
# Generate one GTIN-13 (default)
python3 gtin.py

# Generate five GTIN-12 (UPC-A) numbers
python3 gtin.py --length 12 --count 5

# Short flags work too
python3 gtin.py -l 14 -n 10
```

## How it works

The script generates random digits for the body of the GTIN, then computes the
final check digit using the standard GS1 algorithm (alternating 3/1 weights
from the rightmost position), so every generated number passes checksum
validation.

Note: these are random numbers for testing purposes — they are not registered
with GS1 and may collide with real assigned GTINs.
