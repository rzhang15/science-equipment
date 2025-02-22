library(openalexR)
library(dplyr)
library(ggplot2)
library(here)
library(haven)
library(stringr)
library(purrr)
library(tidyverse)
set.seed(8975)

################################### MAIN ###################################
insts <- read_dta('../output/list_of_insts.dta')
nr <- nrow(insts)
split_insts <- split(insts, rep(1:ceiling(nr/5000), each = 5000, length.out=nr))
num_file <- length(split_insts)
for (q in 1:1) {
  insts <- oa_fetch(
    entity = "institutions",
    id  = split_insts[[q]] %>%  mutate(inst_id = as.character(inst_id)) %>% pull(inst_id),
    verbose = TRUE,
    output = "list"
  )
  N_insts <- length(insts)
  
  
  inst_geo <- lapply(1:N_insts, function(i) {
    if (length(insts[[i]][["id"]])!=0) {
      inst_id <- insts[[i]][["id"]] %>% data.frame
    }
    if (length(insts[[i]][["display_name"]])!=0) {
      inst <-  insts[[i]][["display_name"]] %>% data.frame
    }
    else {
      inst <- c("")%>% data.frame
    }
    if (length(insts[[i]][["country_code"]])!=0) {
      country_code <- insts[[i]][["country_code"]] %>% data.frame
    }
    else {
      country_code <- c("")%>% data.frame
    }
    if (length(insts[[i]][["type"]])!=0) {
      type <- insts[[i]][["type"]] %>% data.frame
    }
    else {
      type <- c("")%>% data.frame
    }
    if (length(insts[[i]][["geo"]][["city"]])!=0) {
      city <- insts[[i]][["geo"]][["city"]]%>% data.frame
    }
    else {
      city <- c("")%>% data.frame
    }
    if (length(insts[[i]][["geo"]][["country"]])!=0) {
      country <- insts[[i]][["geo"]][["country"]]%>% data.frame
    }
    else {
      country <- c("")%>% data.frame
    }
    if (length(insts[[i]][["geo"]][["region"]])!=0) {
      region <- insts[[i]][["geo"]][["region"]]%>% data.frame
    }
    else {
      region <- c("")%>% data.frame
    }
    num_assocs <-length(insts[[i]][["associated_institutions"]])%>% data.frame
    cbind(inst_id, inst, country_code, country, city, region, type, num_assocs)
  }) %>% bind_rows() 
  
  colnames(inst_geo) <- c("inst_id","inst", "country_code", "country", "city", "region", "type", "num_assocs")
  inst_geo <- inst_geo %>%  
    mutate(which_inst = 1:n(), 
           num_assocs = replace(num_assocs, num_assocs == 0, 1)) %>% 
    uncount(num_assocs)
  associated_id <- list()
  associated <- list()
  associated_country <- list()
  associated_type <- list()
  associated_rel <- list()
  for(i in 1:N_insts) {
    N_assocs <- length(insts[[i]][["associated_institutions"]])
    if (N_assocs !=0) {
      for(j in 1:N_assocs) {
        if(length(insts[[i]][["associated_institutions"]][[j]][["id"]])!=0) {
          associated_id<-append(associated_id, insts[[i]][["associated_institutions"]][[j]][["id"]])
        }
        else {
          associated_id<-append(associated_id, list(c("")))
        }
        if(length(insts[[i]][["associated_institutions"]][[j]][["display_name"]])!=0) {
          associated<-append(associated, insts[[i]][["associated_institutions"]][[j]][["display_name"]])
        }
        else {
          associated<-append(associated, list(c("")))
        }
        if(length(insts[[i]][["associated_institutions"]][[j]][["country_code"]])!=0) {
          associated_country<-append(associated_country, insts[[i]][["associated_institutions"]][[j]][["country_code"]])
        }
        else {
          associated_country<-append(associated_country, list(c("")))
        }
        if(length(insts[[i]][["associated_institutions"]][[j]][["type"]])!=0) {
          associated_type<-append(associated_type, insts[[i]][["associated_institutions"]][[j]][["type"]])
        }
        else {
          associated_type<-append(associated_type, list(c("")))
        }
        if(length(insts[[i]][["associated_institutions"]][[j]][["relationship"]])!=0) {
          associated_rel<-append(associated_rel, insts[[i]][["associated_institutions"]][[j]][["relationship"]])
        }
        else {
          associated_rel<-append(associated_rel, list(c("")))
        }
      }
    }
    else {
      associated_id<-append(associated_id, list(c("")))
      associated<-append(associated, list(c("")))
      associated_country<-append(associated_country, list(c("")))
      associated_type<-append(associated_type, list(c("")))
      associated_rel<-append(associated_rel, list(c("")))
    }
  }
  associated_id <- associated_id %>% data.frame %>% t()
  associated <- associated %>% data.frame %>% t()
  associated_country <- associated_country %>% data.frame %>% t()
  associated_type <- associated_type %>% data.frame %>% t()
  associated_rel <- associated_rel %>% data.frame %>% t()
  
  inst_chars <- cbind(inst_geo, associated, associated_id, associated_country, associated_type, associated_rel) %>%
    group_by(inst_id, which_inst) %>% 
    mutate(which_assoc = 1:n(),
           inst_id = str_replace(inst_id, "https://openalex.org/",""),
           associated_id = str_replace(associated_id, "https://openalex.org/","")) 
  
  
  write_dta(inst_chars, paste0("../output/inst_geo_chars", as.character(q), ".dta"))
}
