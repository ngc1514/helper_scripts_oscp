import re
import sys

STATUS_CODES = ["200"]

filename = sys.argv[1]

with open(filename) as f:
    for line in f:
        match = re.search(r"Status:\s*(\d+)", line)
        if match and match.group(1) in STATUS_CODES:
            print(line.rstrip())

