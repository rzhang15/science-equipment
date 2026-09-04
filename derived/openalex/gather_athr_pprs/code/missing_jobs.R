library(dplyr)
library(stringr)
library(haven)

athrs <- read_dta("../external/ids/list_of_athrs.dta") %>% filter(athr_id != "A9999999999")
nr <- nrow(athrs)
total_chunks <- ceiling(nr/500) 

existing_files <- list.files("../output/works/", pattern = "works[0-9]+\\.csv")
existing_nums <- as.numeric(str_extract(existing_files, "[0-9]+"))

all_chunks <- 1:total_chunks
missing_chunks <- setdiff(all_chunks, existing_nums)

saveRDS(missing_chunks, "missing_jobs.rds")

batch_size <- 200
num_jobs_needed <- ceiling(length(missing_chunks) / batch_size)

print(paste("Total missing chunks:", length(missing_chunks)))
print(paste("With batch size", batch_size, "-> Submit array: 1-", num_jobs_needed))
