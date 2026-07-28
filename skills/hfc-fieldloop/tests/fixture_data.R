# Synthetic fixture for hfc-fieldloop regression tests. No real survey data;
# every value here is fabricated. Exercises every M1-M13 module: composite ID
# (household x member), multi-country/timezone, GPS with seeded off-site
# points, ordinal straightlining patterns, sentinel-coded missingness, a
# form-version cutover, seeded duration outliers (both directions), and
# consent/assent/media flags.

build_fixture <- function(seed = 42) {
  suppressPackageStartupMessages({ library(dplyr); library(tibble) })
  set.seed(seed)

  n_hh <- 150
  members_per_hh <- sample(1:3, n_hh, replace = TRUE)
  hhid <- rep(sprintf("HH%03d", seq_len(n_hh)), members_per_hh)
  member <- unlist(lapply(members_per_hh, seq_len))
  n <- length(hhid)

  enumerators <- sprintf("E%02d", 1:6)
  enum_vec <- sample(enumerators, n, replace = TRUE)

  base_dates <- seq(as.Date("2026-01-01"), as.Date("2026-01-20"), by = "day")
  day_vec <- sample(base_dates, n, replace = TRUE)
  hour_vec <- sample(c(8, 9, 10, 11, 14, 15, 16, 2, 3, 22, 23), n, replace = TRUE,
                     prob = c(rep(0.11, 7), rep(0.02, 4)))
  start_dt <- as.POSIXct(paste(day_vec, sprintf("%02d:00:00", hour_vec)), tz = "UTC")

  dur <- round(rnorm(n, 35, 5))
  dur[1:3] <- c(95, 98, 100)   # seeded long-duration outliers
  dur[4:6] <- c(1, 1, 2)       # seeded short-duration outliers
  end_dt <- start_dt + dur * 60

  country_vec <- sample(c("Malawi", "Zambia"), n, replace = TRUE)

  q1 <- sample(1:5, n, replace = TRUE)
  q2 <- sample(1:5, n, replace = TRUE)
  q3 <- sample(1:5, n, replace = TRUE)
  e01_idx <- which(enum_vec == "E01")
  q1[e01_idx] <- 3            # seeded enumerator-level straightlining on q1
  q1[e01_idx[1]] <- 1         # keep one different so it's not literally 100%
  q1[10] <- 4; q2[10] <- 4; q3[10] <- 4   # seeded survey-level straightlining

  age <- sample(18:60, n, replace = TRUE)
  score <- rnorm(n, 50, 10)
  score[6:7] <- c(500, -500)  # seeded numeric outliers

  consent <- sample(c("1", "0"), n, replace = TRUE, prob = c(0.9, 0.1))
  assent <- sample(c("1", "0"), n, replace = TRUE, prob = c(0.85, 0.15))

  form_version <- ifelse(day_vec < as.Date("2026-01-10"), "v1", "v2")
  income <- sample(c(100, 200, 300, 400, 99), n, replace = TRUE, prob = rep(0.2, 5))
  school_vec <- sample(sprintf("SCH%d", 1:4), n, replace = TRUE)
  audio_col <- ifelse(runif(n) < 0.1, "", sprintf("rec_%04d.m4a", seq_len(n)))

  school_center <- setNames(
    list(c(-1.29, 36.82), c(-1.30, 36.83), c(-1.28, 36.81), c(-1.31, 36.80)),
    sprintf("SCH%d", 1:4)
  )
  y_coord <- vapply(seq_len(n), function(i) school_center[[school_vec[i]]][1], numeric(1)) + rnorm(n, sd = 0.001)
  x_coord <- vapply(seq_len(n), function(i) school_center[[school_vec[i]]][2], numeric(1)) + rnorm(n, sd = 0.001)
  gps_outlier_idx <- 8:10
  y_coord[gps_outlier_idx] <- y_coord[gps_outlier_idx] + 0.05
  x_coord[gps_outlier_idx] <- x_coord[gps_outlier_idx] + 0.05

  ds <- tibble(
    hhid = hhid, member = member,
    country_name = country_vec,
    enumeratorid = enum_vec,
    starttime = format(start_dt, "%Y-%m-%d %H:%M:%S"),
    endtime = format(end_dt, "%Y-%m-%d %H:%M:%S"),
    duration = dur,
    q1 = q1, q2 = q2, q3 = q3,
    age = age, score = score, income = income,
    x_coord = x_coord, y_coord = y_coord,
    consent = consent, assent = assent,
    formdef_version = form_version,
    schoolid = school_vec,
    audio_consent = audio_col
  )
  # Seed a few duplicate composite-ID rows (M2)
  ds <- bind_rows(ds, ds[1:3, ])

  list(ds = ds, last_date = as.character(max(day_vec)))
}

#' Build confirmed roles + modules for the fixture, bypassing AskUserQuestion
#' (this is what the "required-fields gate" + module confirm would produce).
build_fixture_config <- function(ds, last_date) {
  roles <- profile_roles(ds)
  roles$id <- c("hhid", "member")
  roles$country_mode <- "multi"
  roles$country_col <- "country_name"
  roles$country_timezone_map <- list(Malawi = "Africa/Blantyre", Zambia = "Africa/Lusaka")
  roles$last_date <- last_date

  modules <- default_modules(roles)
  modules$M1$group_vars <- "schoolid"
  modules$M3$version_col <- "formdef_version"
  modules$M7$vars <- c("income", "age")
  modules$M7$sentinel_codes <- list(income = "99")
  modules$M9$ordinal_vars <- c("q1", "q2", "q3")
  modules$M13$on <- TRUE
  modules$M13$consent <- "consent"
  modules$M13$assent <- "assent"

  list(roles = roles, modules = modules)
}
