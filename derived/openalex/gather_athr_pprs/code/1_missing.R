library(openalexR) 
library(dplyr) 
library(tidyverse)
library(data.table)
library(haven)

set.seed(8975)

# --- SETUP ---
# Load original data to map IDs
athrs <- read_dta("../external/ids/list_of_athrs.dta")  %>% filter(athr_id != "A9999999999")
nr <- nrow(athrs)
split_athr <- split(athrs, rep(1:ceiling(nr/500), each = 500, length.out=nr))

# Load the specific list of chunks we need to do
missing_chunks <- readRDS("missing_jobs.rds")

# --- BATCH LOGIC ---
task_id <- as.numeric(Sys.getenv("SLURM_ARRAY_TASK_ID"))
if (is.na(task_id)) task_id <- 1

# Batch size of 30 ensures ~60 minute runtime
batch_size <- 1 

start_idx <- (task_id - 1) * batch_size + 1
end_idx   <- min(task_id * batch_size, length(missing_chunks))

if (start_idx > length(missing_chunks)) {
  quit(save="no")
}

# Identify which chunks THIS job will run
current_batch <- missing_chunks[start_idx:end_idx]
print(paste("Job", task_id, "processing", length(current_batch), "chunks"))

# --- LOOP ---
for (q in current_batch) {
    try({
        works <- oa_fetch(
            entity = "works", 
            paging = "cursor", 
            per_page = 25,
            api_key = "01bd3ab8d66ee5d53d209f63f2dea37d",
            author.id = split_athr[[q]] %>% pull(athr_id),
            output = "list"
        )
        
        N_articles <- length(works)
        if (N_articles > 0) {
            output <- lapply(1:N_articles, function(i) {
                ids <- works[[i]][["id"]] %>% data.frame
            })
            output <- output %>% bind_rows() %>% distinct() %>% data.frame
            write_csv(output, paste0("../output/works", as.character(q), ".csv"))
        }
    })
}
