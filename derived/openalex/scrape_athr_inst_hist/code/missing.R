library(data.table)
library(haven)
data <- read_dta("../external/ids/list_of_works_15jrnls.dta")

N <- round(nrow(data)/5000)
print(N)

missing_list <- c()

for(i in 1:N) {
    file_path <-  paste0("../output/concepts", i, ".csv")
     if (!file.exists(file_path)) {
         missing_list <- c(missing_list, i)
     }
}

df <- data.frame(segment = missing_list)

write.csv(df, "../temp/missing_segments.csv", row.names = FALSE)
