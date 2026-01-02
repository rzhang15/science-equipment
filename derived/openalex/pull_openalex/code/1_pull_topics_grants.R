library(openalexR)
library(dplyr)
library(ggplot2)
library(here)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)
library(jsonlite)
library(httr)
set.seed(8975)
setwd("~/sci_eq/derived/openalex/pull_openalex/code")
api_key <- "01bd3ab8d66ee5d53d209f63f2dea37d" 

message("Loading PMID file...")
pmid_file <- read_dta('../external/pmids/pmids.dta')
nr <- nrow(pmid_file)

split_pmid <- split(pmid_file, rep(1:ceiling(nr/5000), each = 5000, length.out=nr))
batches <- 4751:5000

message(paste("Total batches to process:", length(batches)))

fetch_batch_all <- function(pmids_vector) {
  ids <- as.character(pmids_vector)
  ids <- ids[!is.na(ids) & ids != "" & ids != "NA"]
  if (length(ids) == 0) return(NULL)
  chunks <- split(ids, ceiling(seq_along(ids) / 50))
  results_list <- list()
  for (chunk in chunks) {
    filter_str <- paste0("pmid:", paste(chunk, collapse = "|"))
    try({
      resp <- GET(
        url = "https://api.openalex.org/works",
        query = list(
          filter = filter_str,
          select = "id,type_crossref,awards,topics", 
          `per-page` = 50,
          api_key = api_key
        )
      )
      
      if (status_code(resp) == 200) {
        json_content <- content(resp, "text", encoding = "UTF-8")
        parsed <- fromJSON(json_content, simplifyVector = FALSE)
        if (!is.null(parsed$results)) {
          results_list <- c(results_list, parsed$results)
        }
      }
    })
    Sys.sleep(0.2)
  }
  return(results_list)
}

# --- MAIN LOOP ---
for (q in batches) {
  message(paste("Processing batch:", q, "/", length(split_pmid)))
  raw_pmids <- split_pmid[[q]] %>% pull(pmid)
  batch_works <- fetch_batch_all(raw_pmids)
  if (is.null(batch_works) || length(batch_works) == 0) {
    message("  No data returned for this batch.")
    next
  }
  
  types_df <- map_dfr(batch_works, function(article) {
    id <- article[["id"]]
    type_cr <- if(!is.null(article[["type_crossref"]])) article[["type_crossref"]] else NA_character_
    tibble(id = id, type_crossref = type_cr)
  })
  
  if (nrow(types_df) > 0) {
    types_df <- types_df %>% 
      mutate(id = str_replace(id, "https://openalex.org/", ""))
    write_csv(types_df, paste0("../output/types", as.character(q), ".csv"))
  }
  
  awards_df <- map_dfr(batch_works, function(article) {
    if (is.null(article[["awards"]]) || length(article[["awards"]]) == 0) return(NULL)
    
    ids <- rep(article[["id"]], length(article[["awards"]]))
    which_grant <- seq_along(article[["awards"]])
    
    get_field <- function(x, f) if(!is.null(x[[f]])) x[[f]] else NA_character_
    
    funder_id <- map_chr(article[["awards"]], ~ get_field(.x, "funder_id"))
    funder_name <- map_chr(article[["awards"]], ~ get_field(.x, "funder_display_name"))
    funder_award_id <- map_chr(article[["awards"]], ~ get_field(.x, "funder_award_id"))
    
    tibble(id = ids, which_grant = which_grant, funder_id = funder_id, 
           funder_name = funder_name, award_id = funder_award_id)
  })
  
  if (nrow(awards_df) > 0) {
    awards_df <- awards_df %>% 
      mutate(id = str_replace(id, "https://openalex.org/", ""),
             funder_id = str_replace(funder_id, "https://openalex.org/", ""))
    write_csv(awards_df, paste0("../output/grants", as.character(q), ".csv"))
  }
  
  topics_df <- map_dfr(batch_works, function(article) {
    if (is.null(article[["topics"]]) || length(article[["topics"]]) == 0) return(NULL)
    
    ids <- rep(article[["id"]], length(article[["topics"]]))
    which_topic <- seq_along(article[["topics"]])
    
    safe_nest <- function(x, k1, k2) {
      if(is.null(x[[k1]]) || is.null(x[[k1]][[k2]])) return(NA_character_)
      return(x[[k1]][[k2]])
    }
    get_field <- function(x, f) if(!is.null(x[[f]])) x[[f]] else NA_character_
    
    topic_id <- map_chr(article[["topics"]], ~ get_field(.x, "id"))
    topic <- map_chr(article[["topics"]], ~ get_field(.x, "display_name"))
    
    subfield_id <- map_chr(article[["topics"]], ~ safe_nest(.x, "subfield", "id"))
    subfield <- map_chr(article[["topics"]], ~ safe_nest(.x, "subfield", "display_name"))
    field_id <- map_chr(article[["topics"]], ~ safe_nest(.x, "field", "id"))
    field <- map_chr(article[["topics"]], ~ safe_nest(.x, "field", "display_name"))
    domain_id <- map_chr(article[["topics"]], ~ safe_nest(.x, "domain", "id"))
    domain <- map_chr(article[["topics"]], ~ safe_nest(.x, "domain", "display_name"))
    
    tibble(ids, which_topic, topic_id, topic, subfield_id, subfield, field, field_id, domain_id, domain)
  })
  
  if (nrow(topics_df) > 0) {
    colnames(topics_df) <- c("id", "which_topic", "topic_id", "topic", "subfield_id", "subfield", "field", "field_id", "domain_id", "domain")
    
    topics_df <- topics_df %>% 
      mutate(id = str_replace(id, "https://openalex.org/", ""), 
             topic_id = str_replace(topic_id, "https://openalex.org/", ""),
             subfield_id = str_replace(subfield_id, "https://openalex.org/subfields/", ""),
             field_id = str_replace(field_id, "https://openalex.org/fields/", ""),
             domain_id = str_replace(domain_id, "https://openalex.org/domains/", ""))
    
    write_csv(topics_df, paste0("../output/topics", as.character(q), ".csv"))
  }
}