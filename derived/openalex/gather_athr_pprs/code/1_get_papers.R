library(openalexR) 
library(dplyr) 
library(ggplot2) 
library(here)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)
library(data.table)

set.seed(8975)

athrs <- read_dta("../external/ids/list_of_athrs.dta")  %>% filter(athr_id != "A9999999999")
nr <- nrow(athrs)

split_athr <- split(athrs, rep(1:ceiling(nr/500), each = 500, length.out=nr))
num_file <- length(split_athr)


task_id <- as.numeric(Sys.getenv("SLURM_ARRAY_TASK_ID"))
if (is.na(task_id)) task_id <- 1

batch_size <- 500

start_q <- (task_id - 1) * batch_size + 1
end_q   <- min(task_id * batch_size, num_file)

print(paste("Job ID:", task_id, "| Processing chunks:", start_q, "to", end_q))


for (q in start_q:end_q) {
    print(paste("Processing chunk:", q))
    
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