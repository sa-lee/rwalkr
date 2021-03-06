#' A simple shiny app for pedestrian data
#' 
#' Provides a GUI to download data of selected sensors over a specified period
#' as a CSV file, accompanied with basic visualisation. 
#'
#' @details It offers some basic plots to give a glimpse of the data over a 
#' short time period. In order to be reproducible, scripting using [`melb_walk`] 
#' or [`melb_walk_fast`] is recommended.
#'
#' @return A shiny app.
#' @export
#'
melb_shine <- function() {
  if (!(requireNamespace("shiny", quietly = TRUE) && 
        utils::packageVersion("shiny") >= "1.0.4")) {
    stop(
      "Packages shiny (>= v1.0.4) required for melb_shine()", ".\n",
      "Please install and try again.", call. = FALSE
    )
  }
  if (!requireNamespace("plotly", quietly = TRUE)) {
    stop(
      "Packages plotly required for melb_shine()", ".\n",
      "Please install and try again.", call. = FALSE
    )
  }
  `%>%` <- plotly::`%>%`
  sensor_df <- pull_sensor() %>% 
    dplyr::mutate(abbr = gsub(" ", "", gsub("[:a-z:]", "", sensor)))

  ui <- shiny::fluidPage(
    shiny::br(),
    shiny::fluidRow(
      shiny::column(
        width = 4,
        shiny::dateRangeInput(
          "date_rng", "Date range:",
          start = Sys.Date() - 3L,
          end = Sys.Date() - 1L,
          min = "2009-06-01",
          max = Sys.Date() - 1L
        ),
        shiny::actionButton(
          "goButton", "Update Date",
          icon = shiny::icon("refresh")
        ),
        shiny::hr(),
        shiny::selectizeInput(
          "SensorInfo", "Sensor filter:",
          choices = sensor_df$sensor,
          multiple = TRUE
        ),
        shiny::downloadButton("downloadCSV", "Download CSV")
      ),
      shiny::column(
        width = 7,
        plotly::plotlyOutput("drawOverlay", height = 320),
        shiny::hr(),
        plotly::plotlyOutput("drawMarker", height = 480)
      )
    )
  )

  server <- function(input, output, session) {
    all_df <- shiny::reactive({
      input$goButton
      shiny::isolate(melb_walk(
        from = input$date_rng[1], to = input$date_rng[2], session = "shiny"
      ))
    })
    ped_df <- shiny::reactive({
      if (is.null(input$SensorInfo)) {
        all_df()
      } else {
        dplyr::filter(all_df(), Sensor %in% input$SensorInfo)
      }
    })

    output$downloadCSV <- shiny::downloadHandler(
      filename = function() {
        paste0("pedestrian-", Sys.Date(), ".csv")
      },
      content = function(file) {
        utils::write.csv(ped_df(), file, quote = FALSE, row.names = FALSE)
      }
    )

    output$drawOverlay <- plotly::renderPlotly({
      ped_dat <- ped_df() %>%
        dplyr::filter(!is.na(Count))
      if (NROW(ped_dat) == 0) {
        plotly::plot_ly(
          x = 1, y = 1, text = "Oops! No data points available."
        ) %>% 
        plotly::add_text()
      } else {
        ped_key <- row.names(ped_dat)
        tsplot <- ped_dat %>%
          dplyr::group_by(Sensor) %>%
          plotly::plot_ly(
            x = ~ Date_Time, y = ~ Count,
            hoverinfo = "text",
            text = ~ paste(
              "Sensor: ", Sensor,
              "<br> Date Time: ", Date_Time,
              "<br> Count:", Count
            ),
            source = "tsplot"
          ) %>%
          plotly::add_lines(alpha = 0.8, key = ~ ped_key)
        click <- plotly::event_data("plotly_click", source = "tsplot")
        if (!is.null(click)) {
          hl_line <- ped_dat[ped_key %in% click$key[1], "Sensor"]
          hl_sensor <- ped_dat %>% dplyr::filter(Sensor %in% hl_line)
          if (nrow(hl_sensor) != 0) # if it's an empty data frame
            tsplot <- plotly::add_lines(
              tsplot, data = hl_sensor, color = I("#d73027")
            )
        }
        plotly::layout(
          tsplot, title = "Time series plot", showlegend = FALSE,
          xaxis = list(title = "Date Time"), yaxis = list(title = "Count")
        )
      }
    })

    output$drawMarker <- plotly::renderPlotly({
      na_df <- ped_df() %>%
        dplyr::left_join(sensor_df, by = c("Sensor" = "sensor")) %>%
        dplyr::mutate(NA_ind = is.na(Count))
      miss_marker <- plotly::plot_ly(
        na_df, hoverinfo = "text",
        text = ~ paste(
          "Sensor:", Sensor,
          "<br> Date Time: ", Date_Time,
          "<br> Missing: ", NA_ind
        )
      ) %>%
        plotly::add_markers(
          x = ~ Date_Time, y = ~ abbr, color = ~ NA_ind,
          colors = c("#1b9e77", "#7570b3")
        )
      plotly::layout(
        miss_marker, title = "Missing value indicator",
        showlegend = FALSE,
        xaxis = list(title = "Date Time"), yaxis = list(title = "")
      )
    })
  }

  shiny::shinyApp(ui, server)
}
