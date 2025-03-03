## ff_scoringhistory (Template) ##

#' Get a dataframe of scoring history, utilizing the ff_scoring and load_player_stats functions.
#'
#' @param conn a conn object created by `ff_connect()`
#' @param season season a numeric vector of seasons (earliest available year is 1999)
#' @param ... other arguments
#'
#' @examples
#' \donttest{
#' try({ # try only shown here because sometimes CRAN checks are weird
#'   template_conn <- ff_template(scoring_type = "sfb11", roster_type = "sfb11")
#'   ff_scoringhistory(template_conn, season = 2020)
#' }) # end try
#' }
#'
#' @describeIn ff_scoringhistory template: returns scoring history in a flat table, one row per player per week.
#'
#' @export
ff_scoringhistory.template_conn <- function(conn, season = 1999:2020, ...) {
  checkmate::assert_numeric(season, lower = 1999, upper = as.integer(format(Sys.Date(), "%Y")))

  # Pull in scoring rules for that league
  league_rules <-
    ff_scoring(conn) %>%
    tidyr::separate(
      col = "range",
      into = c("lower_range", "upper_range"),
      sep = "-(?=[0-9]*$)"
    ) %>%
    dplyr::mutate(dplyr::across(
      .cols = c("lower_range", "upper_range"),
      .fns = as.numeric
    )) %>%
    dplyr::left_join(
      ffscrapr::nflfastr_stat_mapping %>% dplyr::filter(.data$platform == "mfl"),
      by = c("event" = "ff_event")
    ) %>%
    dplyr::select(
      "pos", "points", "lower_range", "upper_range", "event", "points_type", "nflfastr_event", "short_desc"
    )

  # Use custom ffscrapr function to get positions from nflfastR rosters
  fastr_rosters <-
    nflfastr_rosters(seasons = season) %>%
    dplyr::mutate(position = dplyr::if_else(.data$position %in% c("HB", "FB"), "RB", .data$position)) %>%
    dplyr::left_join(
      dp_playerids() %>%
        dplyr::select("mfl_id", "sportradar_id") %>%
        dplyr::filter(!is.na(.data$sportradar_id)),
      by = "sportradar_id"
    )

  # Load stats from nflfastr and map the rules from the internal stat_mapping file
  fastr_weekly <- nflfastr_weekly(seasons = season) %>%
    dplyr::inner_join(fastr_rosters, by = c("player_id" = "gsis_id", "season" = "season")) %>%
    dplyr::select(
      "season", "player_id", "sportradar_id", "mfl_id", "position", "full_name", "recent_team", "week",
      "completions", "attempts", "passing_yards", "passing_tds", "interceptions", "sacks",
      "sack_fumbles_lost", "passing_first_downs", "passing_2pt_conversions", "carries",
      "rushing_yards", "rushing_tds", "rushing_fumbles_lost", "rushing_first_downs",
      "rushing_2pt_conversions", "receptions", "targets", "receiving_yards", "receiving_tds",
      "receiving_fumbles_lost", "receiving_first_downs", "receiving_2pt_conversions",
      "special_teams_tds", "sack_yards", "rushing_fumbles", "receiving_fumbles", "sack_fumbles"
    ) %>%
    tidyr::pivot_longer(
      names_to = "metric",
      cols = c(
        "completions", "attempts", "passing_yards", "passing_tds", "interceptions", "sacks",
        "sack_fumbles_lost", "passing_first_downs", "passing_2pt_conversions", "carries",
        "rushing_yards", "rushing_tds", "rushing_fumbles_lost", "rushing_first_downs",
        "rushing_2pt_conversions", "receptions", "targets", "receiving_yards", "receiving_tds",
        "receiving_fumbles_lost", "receiving_first_downs", "receiving_2pt_conversions",
        "special_teams_tds", "sack_yards", "rushing_fumbles", "receiving_fumbles", "sack_fumbles"
      )
    ) %>%
    dplyr::inner_join(league_rules, by = c("metric" = "nflfastr_event", "position" = "pos")) %>%
    dplyr::filter(.data$value >= .data$lower_range, .data$value <= .data$upper_range) %>%
    dplyr::mutate(
      value = dplyr::case_when(.data$points_type == "once" ~ 1, TRUE ~ .data$value),
      points = .data$value * .data$points
    ) %>%
    dplyr::group_by(.data$season, .data$week, .data$player_id, .data$sportradar_id) %>%
    dplyr::mutate(points = round(sum(.data$points, na.rm = TRUE), 2)) %>%
    dplyr::ungroup() %>%
    dplyr::select("season", "week",
      "gsis_id" = "player_id", "sportradar_id",
      "mfl_id", "player_name" = "full_name", "pos" = "position",
      "team" = "recent_team", "metric", "value", "points"
    ) %>%
    tidyr::pivot_wider(
      id_cols = c(
        "season", "week", "gsis_id", "sportradar_id",
        "mfl_id", "player_name", "pos", "team", "points"
      ),
      names_from = .data$metric,
      values_from = .data$value,
      values_fill = 0,
      values_fn = max
    )

  return(fastr_weekly)
}
