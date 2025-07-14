library(openalexR)
library(dplyr)
library(ggplot2)
library(here)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)
set.seed(8975)

years <- 2000:2024
# nih_funded_papers <- list()
# for (year in years) {
#   var_name <- paste0("nih_funded_papers_", year)  # Create the variable name dynamically
#   nih_funded_papers[[as.character(year)]] <- oa_fetch(
#     entity = "works",
#     primary_topic.domain.id = 1,
#     grants.funder = "F4320332161",
#     publication_year = as.character(year),
#     output = "list"
#   )
# }
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
  pmid <- rep(ifelse(length(article[["ids"]][["pmid"]]) != 0, article[["ids"]][["pmid"]], ""), length(article[["authorships"]]))
  retracted <- rep(ifelse(length(article[["is_retracted"]]) != 0, article[["is_retracted"]], ""), length(article[["authorships"]]))
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

# for (year in years) {
#   var_name <- paste0("dallas_papers_", year)  # Create the variable name dynamically
#    list <- oa_fetch(
#     entity = "works",
#     primary_topic.domain.id = 1,
#     institutions.id = "I162577319",
#     publication_year = as.character(year),
#     output = "list",
#     type = "article"
#   )
#   assign(var_name, list)
# }

for (year in years) {
  works <- oa_fetch(
    entity = "works",
    primary_topic.domain.id = c(1),
    publication_year = as.character(year),
    output = "list",
    type = "article"
  )
  
  au_ids <- map_dfr(works, process_article)
  colnames(au_ids) <- c("id", "abstract_len", "doi", "jrnl", "title", "pub_date", "retracted", "cite_count", "pub_type", "pub_type_crossref", "pmid", "which_athr", "athr_id", "athr_pos", "raw_affl", "athr_name", "num_affls")
  
  au_ids <- au_ids %>%
    mutate(num_affls = replace(num_affls, num_affls == 0, 1)) %>%
    uncount(num_affls)
  
  inst <- list()
  inst_id <- list()
  
  for (i in seq_along(works)) {
    article <- works[[i]]
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
  
  write_csv(affl_list, paste0("../output/openalex_authors", as.character(year), ".csv"))
  grants <- map_dfr(works, function(article) {
    if (length(article[["grants"]]) == 0) return(NULL)
    
    ids <- rep(article[["id"]], length(article[["grants"]]))
    which_grant <- seq_along(article[["grants"]])
    funder_id <- map_chr(article[["grants"]], "funder", .default = NA_character_)
    funder_name <-  map_chr(article[["grants"]], "funder_display_name", .default = NA_character_)
    award_id <-  map_chr(article[["grants"]], "award_id", .default = NA_character_)
    
    tibble(id = ids, which_grant = which_grant, funder_id = funder_id, 
           funder_name = funder_name, award_id = award_id)
  })
  colnames(grants) <- c("id", "which_grant", "funder_id", "funder_name", "award_id")
  if (nrow(grants) != 0) {
    grants <- grants %>% mutate(id = str_replace(as.character(id), "https://openalex.org/", ""),
                                funder_id = str_replace(as.character(funder_id), "https://openalex.org/", ""))
    write_csv(grants, paste0("../output/grants", as.character(year), ".csv"))
  }
  mesh_terms <- map_dfr(works, function(article) {
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
    write_csv(mesh_terms, paste0("../output/mesh_terms", as.character(year), ".csv"))
  }
  
  topics <- map_dfr(works, function(article) {
    if (length(article[["topics"]]) == 0) return(NULL)
    ids <- rep(article[["id"]], length(article[["topics"]]))
    which_topic <- seq_along(article[["topics"]])
    topic_id <- map_chr(article[["topics"]], "id")
    topic <- map_chr(article[["topics"]], "display_name")
    subfield_id <- map_chr(article[["topics"]], ~ .x[["subfield"]][["id"]], .default = NA_character_)
    subfield <- map_chr(article[["topics"]], ~ .x[["subfield"]][["display_name"]], .default = NA_character_)
    field_id <- map_chr(article[["topics"]], ~ .x[["field"]][["id"]], .default = NA_character_)
    field <- map_chr(article[["topics"]], ~ .x[["field"]][["display_name"]], .default = NA_character_)
    domain_id <- map_chr(article[["topics"]], ~ .x[["domain"]][["id"]], .default = NA_character_)
    domain <- map_chr(article[["topics"]], ~ .x[["domain"]][["display_name"]], .default = NA_character_)
    tibble(ids, which_topic, topic_id, topic, subfield_id, subfield, field, field_id, domain_id, domain)
  })
  
  colnames(topics) <- c("id", "which_topic", "topic_id", "topic", "subfield_id", "subfield", "field", "field_id", "domain_id", "domain")
  
  if (nrow(topics) != 0) {
    topics <- topics %>% mutate(id = str_replace(as.character(id), "https://openalex.org/", ""), 
                                topic_id = str_replace(as.character(topic_id), "https://openalex.org/", ""),
                                subfield_id = str_replace(as.character(subfield_id), "https://openalex.org/subfields/", ""),
                                field_id = str_replace(as.character(field_id), "https://openalex.org/fields/", ""),
                                domain_id = str_replace(as.character(domain_id), "https://openalex.org/domains/", ""))
    write_csv(topics, paste0("../output/topics", as.character(year), ".csv"))
  }
}
