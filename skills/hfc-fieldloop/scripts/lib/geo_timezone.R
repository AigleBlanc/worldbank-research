# Country -> IANA timezone lookup for M5 (Irregular Timing).
# No new package dependency (e.g. countrycode) — a small maintained table is
# enough for the common HFC survey footprint. Unmatched countries always fall
# back to a manual AskUserQuestion + Other raw-IANA-string prompt; a resolved
# match is still shown back to the user for confirmation before use (never
# trusted silently — see references/flags.md F24).

COUNTRY_TZ_LOOKUP <- tibble::tribble(
  ~name, ~iso2, ~iso3, ~tz,
  "Afghanistan", "AF", "AFG", "Asia/Kabul",
  "Bangladesh", "BD", "BGD", "Asia/Dhaka",
  "Benin", "BJ", "BEN", "Africa/Porto-Novo",
  "Bolivia", "BO", "BOL", "America/La_Paz",
  "Burkina Faso", "BF", "BFA", "Africa/Ouagadougou",
  "Burundi", "BI", "BDI", "Africa/Bujumbura",
  "Cambodia", "KH", "KHM", "Asia/Phnom_Penh",
  "Cameroon", "CM", "CMR", "Africa/Douala",
  "Central African Republic", "CF", "CAF", "Africa/Bangui",
  "Chad", "TD", "TCD", "Africa/Ndjamena",
  "Colombia", "CO", "COL", "America/Bogota",
  "Democratic Republic of the Congo", "CD", "COD", "Africa/Kinshasa",
  "Republic of the Congo", "CG", "COG", "Africa/Brazzaville",
  "Cote d'Ivoire", "CI", "CIV", "Africa/Abidjan",
  "Egypt", "EG", "EGY", "Africa/Cairo",
  "El Salvador", "SV", "SLV", "America/El_Salvador",
  "Ethiopia", "ET", "ETH", "Africa/Addis_Ababa",
  "Gambia", "GM", "GMB", "Africa/Banjul",
  "Ghana", "GH", "GHA", "Africa/Accra",
  "Guatemala", "GT", "GTM", "America/Guatemala",
  "Guinea", "GN", "GIN", "Africa/Conakry",
  "Guinea-Bissau", "GW", "GNB", "Africa/Bissau",
  "Haiti", "HT", "HTI", "America/Port-au-Prince",
  "Honduras", "HN", "HND", "America/Tegucigalpa",
  "India", "IN", "IND", "Asia/Kolkata",
  "Indonesia", "ID", "IDN", "Asia/Jakarta",
  "Iraq", "IQ", "IRQ", "Asia/Baghdad",
  "Jordan", "JO", "JOR", "Asia/Amman",
  "Kenya", "KE", "KEN", "Africa/Nairobi",
  "Laos", "LA", "LAO", "Asia/Vientiane",
  "Lebanon", "LB", "LBN", "Asia/Beirut",
  "Lesotho", "LS", "LSO", "Africa/Maseru",
  "Liberia", "LR", "LBR", "Africa/Monrovia",
  "Madagascar", "MG", "MDG", "Indian/Antananarivo",
  "Malawi", "MW", "MWI", "Africa/Blantyre",
  "Mali", "ML", "MLI", "Africa/Bamako",
  "Mauritania", "MR", "MRT", "Africa/Nouakchott",
  "Mexico", "MX", "MEX", "America/Mexico_City",
  "Morocco", "MA", "MAR", "Africa/Casablanca",
  "Mozambique", "MZ", "MOZ", "Africa/Maputo",
  "Myanmar", "MM", "MMR", "Asia/Yangon",
  "Nepal", "NP", "NPL", "Asia/Kathmandu",
  "Nicaragua", "NI", "NIC", "America/Managua",
  "Niger", "NE", "NER", "Africa/Niamey",
  "Nigeria", "NG", "NGA", "Africa/Lagos",
  "Pakistan", "PK", "PAK", "Asia/Karachi",
  "Palestine", "PS", "PSE", "Asia/Gaza",
  "Peru", "PE", "PER", "America/Lima",
  "Philippines", "PH", "PHL", "Asia/Manila",
  "Rwanda", "RW", "RWA", "Africa/Kigali",
  "Senegal", "SN", "SEN", "Africa/Dakar",
  "Sierra Leone", "SL", "SLE", "Africa/Freetown",
  "Somalia", "SO", "SOM", "Africa/Mogadishu",
  "South Africa", "ZA", "ZAF", "Africa/Johannesburg",
  "South Sudan", "SS", "SSD", "Africa/Juba",
  "Sri Lanka", "LK", "LKA", "Asia/Colombo",
  "Sudan", "SD", "SDN", "Africa/Khartoum",
  "Tanzania", "TZ", "TZA", "Africa/Dar_es_Salaam",
  "Timor-Leste", "TL", "TLS", "Asia/Dili",
  "Togo", "TG", "TGO", "Africa/Lome",
  "Tunisia", "TN", "TUN", "Africa/Tunis",
  "Uganda", "UG", "UGA", "Africa/Kampala",
  "Vietnam", "VN", "VNM", "Asia/Ho_Chi_Minh",
  "Yemen", "YE", "YEM", "Asia/Aden",
  "Zambia", "ZM", "ZMB", "Africa/Lusaka",
  "Zimbabwe", "ZW", "ZWE", "Africa/Harare"
)

#' Normalize a country string for matching (trim, lowercase, strip punctuation).
.normalize_country <- function(x) {
  x <- tolower(trimws(as.character(x)))
  gsub("[^a-z0-9 ]", "", x)
}

#' Resolve one country string to a timezone. Returns list(tz, matched_name,
#' confidence) with tz = NA_character_ and confidence = "none" on no match.
resolve_country_timezone <- function(country_str) {
  if (is.null(country_str) || is.na(country_str) || !nzchar(trimws(as.character(country_str)))) {
    return(list(tz = NA_character_, matched_name = NA_character_, confidence = "none"))
  }
  q <- .normalize_country(country_str)
  tbl <- COUNTRY_TZ_LOOKUP
  norm_name <- .normalize_country(tbl$name)
  norm_iso2 <- tolower(tbl$iso2)
  norm_iso3 <- tolower(tbl$iso3)

  hit <- which(norm_name == q | norm_iso2 == q | norm_iso3 == q)
  if (length(hit) >= 1) {
    return(list(tz = tbl$tz[hit[1]], matched_name = tbl$name[hit[1]], confidence = "exact"))
  }

  # Loose fallback: substring match either direction (e.g. "Republic of Malawi")
  hit <- which(mapply(function(nm) grepl(nm, q, fixed = TRUE) || grepl(q, nm, fixed = TRUE), norm_name))
  if (length(hit) == 1) {
    return(list(tz = tbl$tz[hit], matched_name = tbl$name[hit], confidence = "fuzzy"))
  }

  list(tz = NA_character_, matched_name = NA_character_, confidence = "none")
}

#' Resolve every distinct value of a country column, for the multi-country
#' confirm gate. Returns a data.frame: country_value, tz, matched_name, confidence.
resolve_country_timezone_column <- function(ds, country_col) {
  if (is.null(country_col) || is.na(country_col) || !country_col %in% names(ds)) {
    return(tibble::tibble(country_value = character(), tz = character(),
                          matched_name = character(), confidence = character()))
  }
  vals <- unique(as.character(ds[[country_col]]))
  vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
  rows <- lapply(vals, function(v) {
    r <- resolve_country_timezone(v)
    tibble::tibble(country_value = v, tz = r$tz %||% NA_character_,
                   matched_name = r$matched_name %||% NA_character_,
                   confidence = r$confidence)
  })
  if (!length(rows)) {
    return(tibble::tibble(country_value = character(), tz = character(),
                          matched_name = character(), confidence = character()))
  }
  dplyr::bind_rows(rows)
}

#' Loosely validate a user-typed IANA timezone string (used when a country
#' has no lookup match and the agent asks the user directly for a raw tz).
is_valid_tz <- function(tz_str) {
  !is.null(tz_str) && !is.na(tz_str) && nzchar(tz_str) && tz_str %in% OlsonNames()
}
