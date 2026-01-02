library(openalexR)
library(dplyr)
library(ggplot2)
library(here)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)
set.seed(8975)
setwd("~/sci_eq/derived/openalex/pull_openalex/code")
pmid_file <- read_dta('../external/pmids/pmids.dta')
nr <- nrow(pmid_file)
split_pmid <- split(pmid_file, rep(1:ceiling(nr/5000), each = 5000, length.out=nr))
num_file <- length(split_pmid)
# 1. Identify missing indices
existing_files <- list.files("../output/", pattern = "openalex_authors\\d+\\.csv")
existing_indices <- as.numeric(gsub("\\D", "", existing_files))
missing_indices <- setdiff(1:5347, existing_indices)

process_article <- function(article) {
  if (length(article[["authorships"]]) == 0) return(NULL)
  
  ids <- rep(article[["id"]], length(article[["authorships"]]))
  abstract_len <- rep(length(article[["abstract_inverted_index"]]), length(article[["authorships"]]))
  doi <- rep(ifelse(length(article[["doi"]]) != 0, article[["doi"]], ""), length(article[["authorships"]]))
  jrnl <- rep(ifelse(length(article[["primary_location"]][["source"]][["display_name"]]) != 0, article[["primary_location"]][["source"]][["display_name"]], ""), length(article[["authorships"]]))
  title <- rep(ifelse(length(article[["title"]]) != 0, article[["title"]], ""), length(article[["authorships"]]))
  pub_date <- rep(ifelse(length(article[["publication_date"]]) != 0, article[["publication_date"]], ""), length(article[["authorships"]]))
  retracted <- rep(ifelse(length(article[["is_retracted"]]) != 0, article[["is_retracted"]], ""), length(article[["authorships"]]))
  cite_count <- rep(ifelse(length(article[["cited_by_count"]]) != 0, article[["cited_by_count"]], ""), length(article[["authorships"]]))
  pub_type <- rep(ifelse(length(article[["type"]]) != 0, article[["type"]], ""), length(article[["authorships"]]))
  pub_type_crossref <- rep(ifelse(length(article[["type_crossref"]]) != 0, article[["type_crossref"]], ""), length(article[["authorships"]]))
  pmid <- rep(article[["ids"]][["pmid"]], length(article[["authorships"]]))
  which_athr <- seq_along(article[["authorships"]])
  
  author_data <- map_dfr(article[["authorships"]], function(authorship) {
    athr_id <- ifelse(is.null(authorship[["author"]][["id"]]), "", authorship[["author"]][["id"]])
    athr_pos <- ifelse(is.null(authorship[["author_position"]][[1]]), "", authorship[["author_position"]][[1]])
    raw_affl <- ifelse(is.null(authorship[["raw_affiliation_string"]][[1]]), "", authorship[["raw_affiliation_string"]][[1]])
    athr_name <- ifelse(is.null(authorship[["author"]][["display_name"]]), "", authorship[["author"]][["display_name"]])
    num_affls <- length(authorship[["institutions"]])
    tibble(athr_id, athr_pos, raw_affl, athr_name, num_affls)
  })
  
  bind_cols(ids, abstract_len, doi, jrnl, title, pub_date, retracted, cite_count, pub_type, pub_type_crossref, pmid, which_athr, author_data)
}

for (q in 1367:1373) {
  works_from_pmids <- oa_fetch(
    entity = "works",
    api_key = "01bd3ab8d66ee5d53d209f63f2dea37d",
    ids.pmid = split_pmid[[q]] %>% mutate(pmid = as.character(pmid)) %>% pull(pmid),
    output = "list"
  )
  au_ids <- map_dfr(works_from_pmids, process_article)
  if (nrow(au_ids) == 0) {
    message(paste("Skipping batch", q, "- no authorship data found"))
    next
  }
  colnames(au_ids) <- c("id", "abstract_len", "doi", "jrnl", "title", "pub_date", "retracted", "cite_count", "pub_type", "pub_type_crossref", "pmid", "which_athr", "athr_id", "athr_pos", "raw_affl", "athr_name", "num_affls")
  
  au_ids <- au_ids %>%
    mutate(num_affls = replace(num_affls, num_affls == 0, 1)) %>%
    uncount(num_affls)
  
  inst <- list()
  inst_id <- list()
  
  for (i in seq_along(works_from_pmids)) {
    article <- works_from_pmids[[i]]
    if (length(article[["authorships"]]) == 0) next
    
    for (authorship in article[["authorships"]]) {
      if (length(authorship[["institutions"]]) == 0) {
        inst <- append(inst, "")
        inst_id <- append(inst_id, "")
      } else {
        for (institution in authorship[["institutions"]]) {
          inst <- append(inst, ifelse(length(institution[["display_name"]]) != 0, institution[["display_name"]], ""))
          inst_id <- append(inst_id, ifelse(length(institution[["id"]]) != 0, institution[["id"]], ""))
        }
      }
    }
  }
  
  affl_list <- au_ids %>% mutate(inst = inst, inst_id = inst_id) %>%
    group_by(id, which_athr) %>%
    mutate(which_affl = 1:n(),
           id = str_replace(as.character(id), "https://openalex.org/", ""),
           pmid = str_replace(pmid, "https://pubmed.ncbi.nlm.nih.gov/", ""),
           athr_id = str_replace(athr_id, "https://openalex.org/", ""),
           inst_id = str_replace(inst_id, "https://openalex.org/", ""))
  
  write_csv(affl_list, paste0("../output/openalex_authors", as.character(q), ".csv"))
  
  mesh_terms <- map_dfr(works_from_pmids, function(article) {
    if (length(article[["mesh"]]) == 0) return(NULL)
    
    ids <- rep(article[["id"]], length(article[["mesh"]]))
    which_mesh <- seq_along(article[["mesh"]])
    terms <- map_chr(article[["mesh"]], "descriptor_name")
    major_topic <- map_lgl(article[["mesh"]], "is_major_topic")
    qualifier <- map_chr(article[["mesh"]], ~ ifelse(is.null(.x[["qualifier_name"]]), "", .x[["qualifier_name"]]))
    
    tibble(ids, which_mesh, terms, major_topic, qualifier)
  })
  
  colnames(mesh_terms) <- c("id", "which_mesh", "term", "is_major_topic", "qualifier_name")
  
  if (nrow(mesh_terms) != 0) {
    mesh_terms <- mesh_terms %>% mutate(id = str_replace(as.character(id), "https://openalex.org/", ""))
    write_csv(mesh_terms, paste0("../output/mesh_terms", as.character(q), ".csv"))
  }
}
