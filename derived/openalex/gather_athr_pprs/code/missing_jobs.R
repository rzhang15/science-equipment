library(dplyr)
library(stringr)
library(haven)

# 1. Calculate total expected chunks (same logic as your main script)
athrs <- read_dta("../external/ids/list_of_athrs.dta") %>% filter(athr_id != "A9999999999")
nr <- nrow(athrs)
# Using your original divisor of 500
total_chunks <- ceiling(nr/500) 

# 2. Find what you already have
existing_files <- list.files("../output/works/", pattern = "works[0-9]+\\.csv")
# Extract the numbers from the filenames
existing_nums <- as.numeric(str_extract(existing_files, "[0-9]+"))

# 3. Identify the missing numbers
all_chunks <- 1:total_chunks
missing_chunks <- setdiff(all_chunks, existing_nums)

# 4. Save this list for the cluster jobs to read
saveRDS(missing_chunks, "missing_jobs.rds")

# 5. Tell you how many jobs to submit
# We will use a larger batch size (e.g., 200) to keep the job count low
batch_size <- 200
num_jobs_needed <- ceiling(length(missing_chunks) / batch_size)

print(paste("Total missing chunks:", length(missing_chunks)))
print(paste("With batch size", batch_size, "-> Submit array: 1-", num_jobs_needed))
