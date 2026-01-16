library(openalexR)
library(dplyr)
library(readr)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)

# --- CONFIGURATION ---
slurm_batch_size <- 250  # How many missing files to process per Slurm Task
output_path <- "../output/works/"
id_file_path <- "../external/ids/list_of_works_all.dta"

# --- SLURM SETUP ---
task_id_env <- Sys.getenv("SLURM_ARRAY_TASK_ID")
if (task_id_env == "") {
  message("No SLURM_ARRAY_TASK_ID found. Defaulting to Task 1 (Local Test).")
  task_id <- 1
} else {
  task_id <- as.numeric(task_id_env)
}

# --- DATA PREP ---
message("Loading ID file...")
id_file <- read_dta(id_file_path)
nr <- nrow(id_file)

# Maintain EXACT split logic as previous runs to ensure file numbering matches
# Batches of 5000 IDs per file/batch
split_id <- split(id_file, rep(1:ceiling(nr/5000), each = 5000, length.out=nr))
total_batches <- length(split_id)
all_batch_nums <- 1:total_batches

# --- IDENTIFY MISSING FILES ---
message("Scanning output directory for existing files...")
existing_files <- list.files(output_path, pattern = "openalex_authors\\d+\\.csv")

# Extract the numbers from filenames like "openalex_authors100.csv"
if(length(existing_files) > 0) {
  existing_nums <- as.numeric(str_extract(existing_files, "\\d+"))
} else {
  existing_nums <- c()
}

# Determine which batches have not been done yet
missing_indices <- setdiff(all_batch_nums, existing_nums)
missing_indices <- sort(missing_indices) # Sort to ensure consistent processing order

total_missing <- length(missing_indices)
message(paste("Total batches defined:", total_batches))
message(paste("Files found:", length(existing_nums)))
message(paste("Missing batches to process:", total_missing))

if (total_missing == 0) {
  message("All files exist. Exiting.")
  quit(save = "no")
}

# --- ASSIGN BATCHES TO THIS SLURM TASK ---
# Calculate which subset of the 'missing_indices' vector this task should handle
start_idx <- ((task_id - 1) * slurm_batch_size) + 1
end_idx   <- task_id * slurm_batch_size

# Handle edge case where the last batch is smaller
if (start_idx > total_missing) {
  message("Task ID is outside the range of missing files. Exiting.")
  quit(save = "no")
}
if (end_idx > total_missing) {
  end_idx <- total_missing
}

# These are the actual batch numbers (q) this task will run
current_job_batches <- missing_indices[start_idx:end_idx]

message(paste("--- SLURM TASK:", task_id, "---"))
message(paste("Processing", length(current_job_batches), "batches."))
message(paste("Batch IDs range from:", min(current_job_batches), "to", max(current_job_batches)))

# --- FUNCTIONS ---
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

# --- MAIN LOOP ---
# Loop only through the specific batches assigned to this task
for (q in c(1005, 1060,1109,1621,2049,2108,2642,10524,13023,15540)) {
  
  # Double check file existence to avoid race conditions (optional but safe)
  outfile <- paste0(output_path, "openalex_authors", as.character(q), ".csv")
  if(file.exists(outfile)) {
    message(paste("Skipping batch", q, "- file already exists"))
    next
  }

  batch_ids <- split_id[[q]] %>% 
    mutate(id = as.character(id)) %>% 
    pull(id)

  if(length(batch_ids) == 0) next
  
  works_from_ids <- tryCatch({
    oa_fetch(
      entity = "works",
      #api_key = "xuconni@gmail.com",
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
    # Optionally write an empty file or log so it doesn't get picked up as "missing" again
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
           
  write_csv(final_df, outfile)
  message(paste("Completed batch", q))
}