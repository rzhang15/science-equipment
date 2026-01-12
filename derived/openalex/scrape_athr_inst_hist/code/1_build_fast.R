library(openalexR)
library(dplyr)
library(readr)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)

chunk_id_env <- Sys.getenv("SLURM_ARRAY_TASK_ID")
if (chunk_id_env == "") {
  message("No SLURM_ARRAY_TASK_ID found. Defaulting to Chunk 1 (Local Test).")
  chunk_id <- 1
} else {
  chunk_id <- as.numeric(chunk_id_env)
}
chunk_id_env <- Sys.getenv("SLURM_ARRAY_TASK_ID")
if (chunk_id_env == "") {
  chunk_id <- 1
} else {
  chunk_id <- as.numeric(chunk_id_env)
}

batch_size <- 1000 

base_start <- ((chunk_id - 1) * batch_size) + 1
base_end   <- chunk_id * batch_size

start_batch <- base_start + 500
end_batch   <- base_end

message(paste("Processing Chunk:", chunk_id, "(Upper Half)"))
message(paste("Batch Range:", start_batch, "to", end_batch))
# --- SETUP ---
set.seed(8975)

id_file <- read_dta('../external/ids/list_of_works_all.dta')
nr <- nrow(id_file)
split_id <- split(id_file, rep(1:ceiling(nr/5000), each = 5000, length.out=nr))
total_batches <- length(split_id)

if (start_batch > total_batches) {
  message("Start batch exceeds total batches. Exiting.")
  quit(save = "no")
}
if (end_batch > total_batches) {
  end_batch <- total_batches
}
extract_article_meta <- function(works_list) {
  tibble(
    id = map_chr(works_list, "id"),
    abstract_len = map_int(works_list, ~ length(.x[["abstract_inverted_index"]])),
    doi = map_chr(works_list, ~ pluck(.x, "doi", .default = "")),
    jrnl = map_chr(works_list, ~ pluck(.x, "primary_location", "source", "display_name", .default = "")),
    title = map_chr(works_list, ~ pluck(.x, "title", .default = "")),
    pub_date = map_chr(works_list, ~ pluck(.x, "publication_date", .default = "")),
    retracted = map_lgl(works_list, ~ pluck(.x, "is_retracted", .default = FALSE)),
    paratext = map_lgl(works_list, ~ pluck(.x, "is_paratext", .default = FALSE)),
    cite_count = map_int(works_list, ~ pluck(.x, "cited_by_count", .default = 0L)),
    pub_type = map_chr(works_list, ~ pluck(.x, "type", .default = "")),
    pmid = map_chr(works_list, ~ pluck(.x, "ids", "pmid", .default = ""))
  )
}
extract_authors_long <- function(works_list) {
  map(works_list, function(article) {
    if (length(article[["authorships"]]) == 0) return(NULL)
    art_id <- article[["id"]]
    
    map(article[["authorships"]], function(authorship) {
      athr_base <- list(
        id = art_id,
        athr_id = pluck(authorship, "author", "id", .default = ""),
        athr_name = pluck(authorship, "author", "display_name", .default = ""),
        athr_pos = pluck(authorship, "author_position", .default = ""),
        raw_affl = pluck(authorship, "raw_affiliation_strings", 1, .default = "")
      )
      institutions <- authorship[["institutions"]]
      
      if (length(institutions) == 0) {
        as_tibble(c(athr_base, list(inst = "", inst_id = "")))
      } else {
        map_dfr(institutions, function(inst_item) {
          as_tibble(c(athr_base, list(
            inst = pluck(inst_item, "display_name", .default = ""),
            inst_id = pluck(inst_item, "id", .default = "")
          )))
        })
      }
    }) %>% list_rbind(names_to = "which_athr")
  }) %>% list_rbind()
}

for (q in start_batch:end_batch) {
  batch_ids <- split_id[[q]] %>% 
    mutate(id = as.character(id)) %>% 
    pull(id)

  if(length(batch_ids) == 0) next
  works_from_ids <- tryCatch({
    oa_fetch(
      entity = "works",
      api_key = "01bd3ab8d66ee5d53d209f63f2dea37d",
      id = batch_ids, 
      output = "list"
    )
  }, error = function(e) {
    message(paste("API Error on batch", q, ":", e$message))
    return(NULL)
  })
  if (is.null(works_from_ids) || length(works_from_ids) == 0) next
  meta_df <- extract_article_meta(works_from_ids)
  authors_df <- extract_authors_long(works_from_ids)
  if (is.null(authors_df) || nrow(authors_df) == 0) {
    message(paste("Skipping batch", q, "- no authorship data found"))
    next
  }
  final_df <- left_join(authors_df, meta_df, by = "id") %>%
    group_by(id, which_athr) %>%
    mutate(which_affl = row_number()) %>%
    ungroup() %>%
    mutate(
      id = str_remove(id, "https://openalex.org/"),
      pmid = str_remove(pmid, "https://pubmed.ncbi.nlm.nih.gov/"),
      athr_id = str_remove(athr_id, "https://openalex.org/"),
      inst_id = str_remove(inst_id, "https://openalex.org/")
    ) %>%
    select(id, abstract_len, doi, jrnl, title, pub_date, retracted, paratext, cite_count, 
           pub_type, pmid, which_athr, athr_id, athr_pos, 
           raw_affl, athr_name, inst, inst_id, which_affl)
  write_csv(final_df, paste0("../output/works/openalex_authors", as.character(q), ".csv"))
  message(paste("Completed batch", q))
}
