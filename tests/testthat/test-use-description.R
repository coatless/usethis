context("use_description")

test_that("build_description_list() defaults to values built into usethis", {
  withr::local_options(list(usethis.description = NULL, devtools.desc = NULL))
  d <- build_description_list()
  expect_equal(d, use_description_defaults()$usethis)
})

test_that("build_description_list(): user's fields > usethis defaults", {
  d <- build_description_list(
    fields = list(Title = "aaa", URL = "https://www.r-project.org")
  )
  ## user's field overwrites default
  expect_identical(d$Title, "aaa")
  ## user's field is novel
  expect_identical(d$URL, "https://www.r-project.org")
  ## from usethis defaults
  expect_match(d$Description, "What the package does")
})

test_that("build_description_list(): usethis options > usethis defaults", {
  withr::local_options(list(usethis.description = list(
    License = "BSD_2_clause"
  )))
  d <- build_description_list()
  ## from usethis options
  expect_identical(d$License, "BSD_2_clause")
  ## from usethis defaults
  expect_match(d$Description, "What the package does")
})

test_that("build_description_list(): devtools options can be picked up", {
  withr::local_options(list(
    usethis.description = NULL,
    devtools.desc = list(License = "LGPL-3")
  ))
  d <- build_description_list()
  ## from devtools options
  expect_identical(d$License, "LGPL-3")
  ## from usethis defaults
  expect_match(d$Description, "What the package does")
})

test_that("build_description_list(): user's fields > options > defaults", {
  withr::local_options(list(
    usethis.description = list(Version = "4.0.0")
  ))
  d <- build_description_list(fields = list(Title = "aaa"))
  ## from user's fields
  expect_identical(d$Title, "aaa")
  ## from usethis options
  expect_identical(d$Version, "4.0.0")
  ## from usethis defaults
  expect_match(d$Description, "What the package does")
})

test_that("default description is tidy", {
  withr::local_options(list(usethis.description = NULL, devtools.desc = NULL))
  scoped_temporary_package()
  desc_lines_before <- read_utf8(proj_path("DESCRIPTION"))
  use_tidy_description()
  desc_lines_after <- read_utf8(proj_path("DESCRIPTION"))
  expect_identical(desc_lines_before, desc_lines_after)
})

test_that("valid CRAN names checked", {
  withr::local_options(list(usethis.description = NULL, devtools.desc = NULL))
  scoped_temporary_package(dir = file_temp(pattern = "invalid_pkg_name"))
  expect_error_free(use_description(check_name = FALSE))
  expect_error(
    use_description(check_name = TRUE),
    "is not a valid package name",
    class = "usethis_error"
  )
})

