library(httr)
library(jsonlite)

# Test with all fields
url1 <- "https://api.census.gov/data/timeseries/intltrade/imports/hs?get=CON_VAL_MO,GEN_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,I_COMMODITY&COMM_LVL=HS10&time=2025-01&CTY_CODE=5700"
cat("Test 1 (all fields, China Jan 2025):\n")
r1 <- GET(url1, timeout(60))
cat("  Status:", status_code(r1), "Size:", nchar(content(r1, "text", encoding="UTF-8")), "\n")

# Test without CON_VAL_MO
url2 <- "https://api.census.gov/data/timeseries/intltrade/imports/hs?get=GEN_VAL_MO,CAL_DUT_MO,DUT_VAL_MO,I_COMMODITY&COMM_LVL=HS10&time=2025-01&CTY_CODE=5700"
cat("Test 2 (no CON_VAL, China Jan 2025):\n")
r2 <- GET(url2, timeout(60))
cat("  Status:", status_code(r2), "Size:", nchar(content(r2, "text", encoding="UTF-8")), "\n")

# Test with just GEN_VAL (what worked before)
url3 <- "https://api.census.gov/data/timeseries/intltrade/imports/hs?get=GEN_VAL_MO,I_COMMODITY&COMM_LVL=HS10&time=2025-01&CTY_CODE=5700"
cat("Test 3 (just GEN_VAL, China Jan 2025):\n")
r3 <- GET(url3, timeout(60))
cat("  Status:", status_code(r3), "Size:", nchar(content(r3, "text", encoding="UTF-8")), "\n")

# If test 1 works, check the header
if (status_code(r1) == 200) {
  txt <- content(r1, "text", encoding="UTF-8")
  parsed <- fromJSON(txt)
  cat("\nTest 1 header:", parsed[1,], "\n")
  cat("Rows:", nrow(parsed) - 1, "\n")
} else if (status_code(r2) == 200) {
  txt <- content(r2, "text", encoding="UTF-8")
  parsed <- fromJSON(txt)
  cat("\nTest 2 header:", parsed[1,], "\n")
  cat("Rows:", nrow(parsed) - 1, "\n")
}
