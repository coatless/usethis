#' Initialise a git repository
#'
#' `use_git()` initialises a Git repository and adds important files to
#' `.gitignore`. If user consents, it also makes an initial commit.
#'
#' @param message Message to use for first commit.
#' @family git helpers
#' @export
#' @examples
#' \dontrun{
#' use_git()
#' }
use_git <- function(message = "Initial commit") {
  if (uses_git()) {
    return(invisible())
  }

  ui_done("Initialising Git repo")
  git_init()

  use_git_ignore(c(".Rhistory", ".RData", ".Rproj.user"))
  git_ask_commit(message, untracked = TRUE)

  restart_rstudio("A restart of RStudio is required to activate the Git pane")
  invisible(TRUE)
}

git_ask_commit <- function(message, untracked = FALSE) {
  if (!interactive() || !uses_git()) {
    return(invisible())
  }

  paths <- unlist(git_status(untracked = untracked), use.names = FALSE)
  if (length(paths) == 0) {
    return(invisible())
  }

  paths <- sort(paths)

  ui_paths <- purrr::map_chr(proj_path(paths), ui_path)
  n <- length(ui_paths)
  if (n > 20) {
    ui_paths <- c(ui_paths[1:20], "...")
  }

  ui_line(c(
    "There are {n} uncommitted files:",
    paste0("* ", ui_paths)
  ))

  if (ui_yeah("Is it ok to commit them?")) {
    ui_done("Adding files")
    repo <- git_repo()
    git2r::add(repo, paths)
    ui_done("Commit with message {ui_value(message)}")
    git2r::commit(repo, message)
  }
  invisible()
}

#' Add a git hook
#'
#' Sets up a git hook using specified script. Creates hook directory if
#' needed, and sets correct permissions on hook.
#'
#' @param hook Hook name. One of "pre-commit", "prepare-commit-msg",
#'   "commit-msg", "post-commit", "applypatch-msg", "pre-applypatch",
#'   "post-applypatch", "pre-rebase", "post-rewrite", "post-checkout",
#'   "post-merge", "pre-push", "pre-auto-gc".
#' @param script Text of script to run
#' @family git helpers
#' @export
use_git_hook <- function(hook, script) {
  check_uses_git()

  hook_path <- proj_path(".git", "hooks", hook)
  create_directory(path_dir(hook_path))

  write_over(hook_path, script)
  file_chmod(hook_path, "0744")

  invisible()
}

#' Tell git to ignore files
#'
#' @param ignores Character vector of ignores, specified as file globs.
#' @param directory Directory relative to active project to set ignores
#' @family git helpers
#' @export
use_git_ignore <- function(ignores, directory = ".") {
  write_union(proj_path(directory, ".gitignore"), ignores)
}

#' Configure Git
#'
#' Sets Git options, for either the user or the project ("global" or "local", in
#' Git terminology).
#'
#' @param ... Name-value pairs.
#' @return Invisibly, the previous values of the modified components.
#' @inheritParams edit
#'
#' @family git helpers
#' @export
#' @examples
#' \dontrun{
#' # set the user's global user.name and user.email
#' use_git_config(user.name = "Jane", user.email = "jane@example.org")
#'
#' # set the user.name and user.email locally, i.e. for current repo/project
#' use_git_config(
#'   scope = "project",
#'   user.name = "Jane",
#'   user.email = "jane@example.org"
#' )
#' }
use_git_config <- function(scope = c("user", "project"), ...) {
  scope <- match.arg(scope)

  if (scope == "user") {
    git_config(...)
  } else {
    check_uses_git()
    git_config(..., .repo = git_repo())
  }
}

#' Produce or register git protocol
#'
#' Git operations that address a remote use a so-called "transport protocol".
#' usethis supports SSH and HTTPS. The protocol affects two things:
#'   * The default URL format for repos with no existing remote protocol:
#'     - `protocol = "ssh"` implies `git@@github.com:<OWNER>/<REPO>.git`
#'     - `protocol = "https"` implies `https://github.com/<OWNER>/<REPO>.git`
#'   * The strategy for creating `credentials` when none are given. See
#'     [git_credentials()] for details.
#' Two helper functions are available:
#'   * `git_protocol()` returns the user's preferred protocol, if known, and,
#'     otherwise, asks the user (interactive session) or defaults to SSH
#'     (non-interactive session).
#'   * `use_git_protocol()` allows the user to set the git protocol, which is
#'     stored in the `usethis.protocol` option.
#' Any interactive choice re: `protocol` comes with a reminder of how to set the
#' protocol at startup by setting an option in `.Rprofile`:
#' ```
#' options(usethis.protocol = "ssh")
#' ## or
#' options(usethis.protocol = "https")
#' ```
#'
#' @param protocol Optional. Should be "ssh" or "https", if specified. Defaults
#'   to the option `usethis.protocol` and, if unset, to an interactive choice
#'   or, in non-interactive sessions, "ssh". `NA` triggers the interactive menu.
#'
#' @return "ssh" or "https"
#' @export
#'
#' @examples
#' \dontrun{
#' ## consult the option and maybe get an interactive menu
#' git_protocol()
#'
#' ## explicitly set the protocol
#' use_git_protocol("ssh")
#' use_git_protocol("https")
#' }
git_protocol <- function() {
  protocol <- getOption(
    "usethis.protocol",
    default = if (interactive()) NA else "ssh"
  )

  ## this is where a user-supplied protocol gets checked, because
  ## use_git_protocol() shoves it in the option unconditionally and calls this
  bad_protocol <- length(protocol) != 1 ||
    ! (tolower(protocol) %in% c("ssh", "https", NA))
  if (bad_protocol) {
    options(usethis.protocol = NULL)
    ui_stop(
      "{ui_code('protocol')} must be one of {ui_value('ssh')}, \\
       {ui_value('https')}', or {ui_value('NA')}."
    )
  }

  if (is.na(protocol)) {
    protocol <- choose_protocol()
    if (is.null(protocol)) {
      ui_stop(
      "{ui_code('protocol')} must be either {ui_value('ssh')} or \\
       {ui_value('https')}'."
      )
    }
    code <- glue("options(usethis.protocol = \"{protocol}\")")
    ui_todo(c(
      "Tip: To suppress this menu in future, put",
      "{ui_code(code)}",
      "in your script or in a user- or project-level startup file, {ui_value('.Rprofile')}.",
      "Call {ui_code('usethis::edit_r_profile()')} to open it for editing."
    ))
  }

  protocol <- match.arg(tolower(protocol), c("ssh", "https"))
  options("usethis.protocol" = protocol)
  getOption("usethis.protocol")
}

#' @rdname git_protocol
#' @export
use_git_protocol <- function(protocol) {
  options("usethis.protocol" = protocol)
  git_protocol()
}

choose_protocol <- function() {
  ## intercept with our internal interactive()
  if (!interactive()) {
    return(invisible())
  }
  choices <- c(
    ssh   = "ssh   <-- presumes that you have set up ssh keys",
    https = "https <-- choose this if you don't have ssh keys (or don't know if you do)"
  )
  choice <- utils::menu(
    choices = choices,
    title = "Which git protocol to use? (enter 0 to exit)"
  )
  if (choice == 0) {
    invisible()
  } else {
    names(choices)[choice]
  }
}

#' Configure and report Git remotes
#'
#' Two helpers are available:
#'   * `use_git_remote()` sets the remote associated with `name` to `url`.
#'   * `git_remotes()` reports the configured remotes, similar to
#'     `git remote -v`.
#'
#' @param name A string giving the short name of a remote.
#' @param url A string giving the url of a remote.
#' @param overwrite Logical. Controls whether an existing remote can be
#'   modified.
#'
#' @return Named list of Git remotes.
#' @export
#'
#' @examples
#' \dontrun{
#' # see current remotes
#' git_remotes()
#'
#' # add new remote named 'foo', a la `git remote add <name> <url>`
#' use_git_remote(name = "foo", url = "https://github.com/<OWNER>/<REPO>.git")
#'
#' # remove existing 'foo' remote, a la `git remote remove <name>`
#' use_git_remote(name = "foo", url = NULL, overwrite = TRUE)
#'
#' # change URL of remote 'foo', a la `git remote set-url <name> <newurl>`
#' use_git_remote(
#'   name = "foo",
#'   url = "https://github.com/<OWNER>/<REPO>.git",
#'   overwrite = TRUE
#' )
#'
#' # Scenario: Fix remotes when you cloned someone's repo, but you should
#' # have fork-and-cloned (in order to make a pull request).
#'
#' # Store origin = main repo's URL, e.g., "git@github.com:<OWNER>/<REPO>.git"
#' upstream_url <- git_remotes()[["origin"]]
#'
#' # IN THE BROWSER: fork the main GitHub repo and get your fork's remote URL
#' my_url <- "git@github.com:<ME>/<REPO>.git"
#'
#' # Rotate the remotes
#' use_git_remote(name = "origin", url = my_url)
#' use_git_remote(name = "upstream", url = upstream_url)
#' git_remotes()
#'
#' # Scenario: Add upstream remote to a repo that you fork-and-cloned, so you
#' # can pull upstream changes.
#' # Note: If you fork-and-clone via `usethis::create_from_github()`, this is
#' # done automatically!
#'
#' # Get URL of main GitHub repo, probably in the browser
#' upstream_url <- "git@github.com:<OWNER>/<REPO>.git"
#' use_git_remote(name = "upstream", url = upstream_url)
#' }
use_git_remote <- function(name = "origin", url, overwrite = FALSE) {
  stopifnot(is_string(name))
  stopifnot(is.null(url) || is_string(url))
  stopifnot(rlang::is_true(overwrite) || rlang::is_false(overwrite))

  repo <- git_repo()
  remotes <- git_remotes()

  if (name %in% names(remotes) && !overwrite) {
    ui_stop("Remote {ui_value(name)} already exists. Use \\
            {ui_code('overwrite = TRUE')} to edit it anyway.")
  }

  if (name %in% names(remotes)) {
    if (is.null(url)) {
      git2r::remote_remove(repo = repo, name = name)
    } else {
      git2r::remote_set_url(repo = repo, name = name, url = url)
    }
  } else {
    git2r::remote_add(repo = repo, name = name, url = url)
  }

  invisible(git_remotes())
}

#' @rdname use_git_remote
#' @export
git_remotes <- function() {
  repo <- git_repo()
  rnames <- git2r::remotes(repo)
  if (length(rnames) == 0) {
    return(NULL)
  }
  stats::setNames(as.list(git2r::remote_url(repo, rnames)), rnames)
}

git2r_env <- new.env(parent = emptyenv())
have_git2r_credentials <- function() rlang::env_has(git2r_env, "credentials")

#' Produce or register git credentials
#'
#' Credentials are needed for git operations like `git push` that address a
#' remote, typically GitHub. usethis uses the git2r package. git2r tries to use
#' the same credentials as command line git, but sometimes fails. usethis tries
#' to increase the chance that things "just work" and, when they don't, to
#' provide the user a way to intervene:
#'   * `git_credentials()` returns any `credentials` that have been registered
#'     with `use_git_credentials()` and, otherwise, implements usethis's
#'     default strategy.
#'   * `use_git_credentials()` allows you to register `credentials` explicitly
#'     for use in all usethis functions in an R session. Do this only after
#'     proven failure of the defaults.
#'
#' @section Default credentials:
#'
#'   If the default behaviour of usethis + git2r works, rejoice and leave well
#'   enough alone. Keep reading if you need more control or understanding.
#'
#' @section SSH credentials:
#'
#' For `protocol = "ssh"`, by default, usethis passes `NULL` credentials
#' to git2r. This will work if you have the exact configuration expected by
#' git2r:
#'
#' 1. Your public and private keys are in the default locations,
#' `~/.ssh/id_rsa.pub` and `~/.ssh/id_rsa`, respectively.
#' 1. All the relevant software agrees on the definition of `~/`, i.e.
#' your home directory. This is harder than it sounds on Windows.
#' 1. Your `ssh-agent` is configured to manage your SSH passphrase, if you have
#' one. This too can be a problem on Windows. Read more about SSH setup in
#' [Happy Git and GitHub for the useR](https://happygitwithr.com/ssh-keys.html),
#' especially the [troubleshooting
#' section](https://happygitwithr.com/ssh-keys.html#ssh-troubleshooting).
#'
#' If the `NULL` default doesn't work, you can make `credentials` explicitly
#' with [git2r::cred_ssh_key()] and register that with
#' `use_git_credentials()` for the rest of the session:
#' ```
#' my_cred <- git2r::cred_ssh_key(
#'    publickey  = "path/to/your/id_rsa.pub",
#'    privatekey = "path/to/your/id_rsa",
#'    # include / omit passphrase as appropriate to your situation
#'    passphrase = askpass::askpass()
#' )
#' use_git_credentials(credentials = my_cred)
#' ```
#' For the remainder of the session, `git_credentials()` will return
#' `my_cred`.
#'
#' @section HTTPS credentials:
#'
#'   For `protocol = "https"`, we must send username and password. It is
#'   possible that your OS has cached this and git2r will successfully use that.
#'   However, usethis can offer even more chance of success in the HTTPS case.
#'   GitHub also accepts a personal access token (PAT) via HTTPS. If
#'   `credentials = NULL` and a PAT is available, we send it. Preference is
#'   given to any `auth_token` that is passed explicitly. Otherwise,
#'   [github_token()] is called. If a PAT is found, we make an HTTPS
#'   credential with [git2r::cred_user_pass()]. The PAT is sent as the password
#'   and dummy text is sent as the username (the PAT is what really matters in
#'   this case). You can also register an explicit credential yourself in a
#'   similar way:
#' ```
#' my_cred <- git2r::cred_user_pass(
#'   username = "janedoe",
#'   password = askpass::askpass()
#' )
#' use_git_credentials(credentials = my_cred)
#' ```
#'   For the remainder of the session, `git_credentials()` will return
#'   `my_cred`.
#'
#' @inheritParams git_protocol
#' @param auth_token GitHub personal access token (PAT).
#' @param credentials A git2r credential object produced with
#'   [git2r::cred_env()], [git2r::cred_ssh_key()], [git2r::cred_token()], or
#'   [git2r::cred_user_pass()].
#'
#' @return Either `NULL` or a git2r credential object, invisibly, i.e.
#'   something to be passed to git2r as `credentials`.
#' @export
#'
#' @examples
#' git_credentials()
#' git_credentials(protocol = "ssh")
#'
#' \dontrun{
#' # these calls look for a GitHub PAT
#' git_credentials(protocol = "https")
#' git_credentials(protocol = "https", auth_token = "MY_GITHUB_PAT")
#' }
git_credentials <- function(protocol = git_protocol(),
                            auth_token = github_token()) {
  if (have_git2r_credentials()) {
    return(git2r_env$credentials)
  }

  if (is.null(protocol) || protocol == "ssh") {
    return(NULL)
  }

  if (have_github_token(auth_token)) {
    git2r::cred_user_pass("EMAIL", check_github_token(auth_token))
  } else {
    NULL
  }
}

#' @rdname git_credentials
#' @export
use_git_credentials <- function(credentials) {
  git2r_env$credentials <- credentials
  invisible(git_credentials())
}

#' git/GitHub sitrep
#'
#' Get a situation report on your current git/GitHub status. Useful for
#' diagnosing problems. [git_vaccinate()] adds some basic R- and RStudio-related
#' entries to the user-level git ignore file.
#' @export
#' @examples
#' git_sitrep()
git_sitrep <- function() {
  # git global ----------------------------------------------------------------
  hd_line("Git config (global)")
  kv_line("Name", git_config_get("user.name", global = TRUE))
  kv_line("Email", git_config_get("user.email", global = TRUE))
  ## TODO: forward info from the credentials package once we start using it
  ## and it reflects the credentials situation usethis will actually meet
  ## e.g., git version, HTTPS credential helpers, SSH keys, etc.
  kv_line("Vaccinated", git_vaccinated())

  # git project ---------------------------------------------------------------
  if (proj_active() && uses_git()) {
    local <- git2r::config(git_repo())$local
    if (any(c("user.name", "user.email") %in% names(local))) {
      hd_line("Git config (project)")
      kv_line("Name", git_config_get("user.name"))
      kv_line("Email", git_config_get("user.email"))
    }
  }

  # usethis + git2r ----------------------------------------------------------
  hd_line("usethis + git2r")
  kv_line("Default usethis protocol", getOption("usethis.protocol"))
  kv_line("git2r supports SSH", git2r::libgit2_features()$ssh)
  credentials_value <- if (have_git2r_credentials()) {
    glue("<user-provided git2r credential object with class {class(git_credentials())}>")
  } else {
    "<usethis + git2r default behaviour>"
  }
  kv_line("Credentials", credentials_value)

  # github user ---------------------------------------------------------------
  hd_line("GitHub")
  have_token <- have_github_token()
  if (have_token) {
    kv_line("Personal access token", "<found in env var>")
    tryCatch(
      {
        who <- gh::gh_whoami(github_token())
        kv_line("User", who$login)
        kv_line("Name", who$name)
      },
      http_error_401 = function(e) ui_oops("Token is invalid."),
      error = function(e) ui_oops("Can't validate token. Is the network reachable?")
    )
    tryCatch(
      {
        emails <- unlist(gh::gh("/user/emails", .token = github_token()))
        emails <- emails[names(emails) == "email"]
        kv_line("Email(s)", emails)
      },
      http_error_404 = function(e) kv_line("Email(s)", "<unknown>"),
      error = function(e) ui_oops("Can't validate token. Is the network reachable?")
    )
  } else {
    kv_line("Personal access token", NULL)
  }

  # repo overview -------------------------------------------------------------
  hd_line("Repo")
  withr::with_options(
    list(usethis.quiet = TRUE),
    try(proj_get(), silent = TRUE)
  )
  if (!proj_active()) {
    ui_info("No active usethis project.")
    return(invisible())
  }

  if (!uses_git()) {
    ui_info("Active project is not a Git repo.")
    return(invisible())
  }

  kv_line("Path", git_repo()$path)
  branch <- tryCatch(git_branch_name(), error = function(e) NULL)
  tracking_branch <- if (is.null(branch)) NULL else git_branch_tracking()
  ## TODO: rework when ui_*() functions make it possible to do better
  branch <- if (is.null(branch)) "<unset>" else branch
  tracking_branch <- if (is.null(tracking_branch)) "<unset>" else tracking_branch
  cat_line("* ", "Local branch -> remote tracking branch: ",
           ui_value(branch), " -> ", ui_value(tracking_branch))

  # PR outlook -------------------------------------------------------------
  hd_line("GitHub pull request readiness")
  if (is.null(github_remote("origin")) && is.null(github_remote("upstream"))) {
    ui_info(
      "
      This repo has neither {ui_value('origin')} nor {ui_value('upstream')} \\
      remote on GitHub.com.
      "
    )
    return(invisible())
  }

  origin   <- git_remote_scrutinize("origin", have_token)
  upstream <- git_remote_scrutinize("upstream", have_token)

  kv_line("origin", github_remote_report(origin))
  kv_line("upstream", github_remote_report(upstream))
}

git_remote_scrutinize <- function(name, have_token = have_github_token()) {
  out <- list(
    exists = FALSE,
    is_github = NA,
    spec = NA,
    perms = NA_character_,
    is_fork = NA,
    fork_spec = NA_character_
  )
  remotes <- git_remotes()
  if (is.null(remotes)) {
    return(out)
  }

  if (is.null(remotes[[name]])) {
    return(out)
  }
  out$exists <- TRUE

  gh_remote <- github_remote(name)
  if (is.null(gh_remote)) {
    out$is_github <- FALSE
    return(out)
  }
  out$is_github <- TRUE
  out$spec <- github_repo_spec(name)

  gh_GET <- if (have_token) gh::gh(glue("/repos/{out$spec}")) else NULL
  if (is.null(gh_GET)) {
    return(out)
  }
  out$perms <- if (isTRUE(gh_GET$permissions$push)) "can push" else "read only"
  out$is_fork <- isTRUE(gh_GET$fork)

  if (!out$is_fork) {
    return(out)
  }
  out$fork_spec <- gh_GET$parent$full_name

  out
}

github_remote_report <- function(info) {
  if (!info$exists) {
    return("<no such remote>")
  }
  if (!info$is_github) {
    return("<not a GitHub remote>")
  }
  out <- info[c("spec", "perms")]
  if (isTRUE(info$is_fork)) {
    out <- c(out, glue("forked from {info$fork_spec}"))
  }
  out
}

# Vaccination -------------------------------------------------------------

#' Vaccinate your global git ignore
#'
#' Adds `.DS_Store`, `.Rproj.user`, and `.Rhistory` to your global
#' `.gitignore`. This is good practices as it ensures that you will never
#' accidentally leak credentials to GitHub.
#'
#' @export
git_vaccinate <- function() {
  path <- git_ignore_path("user")
  write_union(path, git_global_ignore)
}

git_vaccinated <- function() {
  path <- git_ignore_path("user")
  if (!file_exists(path)) {
    return(FALSE)
  }

  lines <- read_utf8(path)
  all(git_global_ignore %in% lines)
}

git_global_ignore <- c(
  ".Rproj.user",
  ".Rhistory",
  ".Rdata",
  ".DS_Store"
)
