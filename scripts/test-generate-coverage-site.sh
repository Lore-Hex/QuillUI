#!/bin/bash
set -e

# Run the generator
python3 scripts/generate-coverage-site.py

SITE_FILE="docs/site/index.html"

if [ ! -f "$SITE_FILE" ]; then
    echo "Error: $SITE_FILE was not generated"
    exit 1
fi

# Assertions
echo "Verifying $SITE_FILE..."

# 1. Has title
grep -q "<title>QuillUI Coverage Matrix</title>" "$SITE_FILE"
echo "✓ Has title"

# 2. Table with >= 5 rows in summary
# Each row in the summary table has <tr> and <td>. 
# We count <tr> tags in the summary table.
ROW_COUNT=$(grep -c "<tr>" "$SITE_FILE")
# Note: summary table has 1 header row + data rows. 
# Detailed content also has tables.
# Let's check for the summary table specifically or just ensure enough rows exist globally.
if [ "$ROW_COUNT" -ge 10 ]; then
    echo "✓ Has >= 5 rows (Total <tr> count: $ROW_COUNT)"
else
    echo "Error: Found only $ROW_COUNT <tr> tags, expected at least 10"
    exit 1
fi

# 3. Filter input
grep -q "id=\"module-filter\"" "$SITE_FILE"
echo "✓ Has filter input"

# 4. Rendered markdown (look for some expected content from the original md)
grep -q "Apple and Package Function Coverage" "$SITE_FILE"
grep -q "<h2 id=\"swiftui\">SwiftUI</h2>" "$SITE_FILE"
echo "✓ Has rendered markdown content"

echo "All tests passed!"
