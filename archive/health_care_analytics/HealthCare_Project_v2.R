#clear workspace
rm(list = ls())

#====library bank====
suppressMessages(library(tidyverse,
                         warn.conflicts = F,
                         quietly = T))
library(RODBC)
library(lubridate, warn.conflicts = F)
library(scales, warn.conflicts = F)

#====connect to database====
access_database <- paste0("F:/School/Tippie_Business Analytics/Health Care Analytics", "/openmrs.accdb") #database locaction

openmrs <- odbcDriverConnect(paste0("Driver={Microsoft Access Driver (*.mdb, *.accdb)};DBQ=",            #connect to
                                    access_database))                                                    #openmrs database


#====reading in dataset====
mrs_patient <- sqlFetch(openmrs, "mrs_patient",                 #what table to `fetch` from the `openmrs` database we connected to
                        as.is = FALSE,
                        stringsAsFactors = FALSE,
                        na.strings = c("", "N/A")) %>%
  filter(!is.na(birthdate)) %>%                                  #filter out blank entries
  select(patient_id,                                             #call out columns needed
         gender,
         birthdate,
         tribe_id = tribe,
         city_village,
         country)

mrs_obs <- sqlFetch(openmrs, "mrs_obs",
                    as.is = F,
                    stringsAsFactors = FALSE,
                    na.strings = c("", "N/A")) %>%
  select(obs_id,
         patient_id,
         encounter_id,
         concept_id,
         obs_datetime,
         value_coded,
         value_numeric,
         comments)


mrs_concept <- sqlFetch(openmrs, "mrs_concept",
                        as.is = F,
                        stringsAsFactors = FALSE,
                        na.strings = c("", "N/A")) %>%
  select(concept_id,
         concept_name,
         retired,
         short_name,
         description,
         datatype,
         concept_class,
         is_set,
         hi_absolute,
         hi_critical,
         hi_normal,
         low_absolute,
         low_critical,
         low_normal,
         units,
         precise)

mrs_encounter <- sqlFetch(openmrs, "mrs_encounter",
                          as.is = F,
                          stringsAsFactors = FALSE,
                          na.strings = c("", "N/A")) %>%
  select(encounter_id,
         encounter_type_id = encounter_type,
         patient_id,
         encounter_datetime)


mrs_encounter_type <- sqlFetch(openmrs, "mrs_encounter_type",
                               as.is = F,
                               stringsAsFactors = FALSE,
                               na.strings = c("", "N/A")) %>%
  select(encounter_type_id,
         encounter_type_name = name,
         encounter_description = description)

mrs_tribe <- sqlFetch(openmrs, "mrs_tribe",
                      as.is = F,
                      stringsAsFactors = FALSE,
                      na.strings = c("", "N/A")) %>%
  select(tribe_id, tribe_name = name)

mrs_program <- sqlFetch(openmrs, "mrs_program",
                        as.is = F,
                        stringsAsFactors = FALSE,
                        na.strings = c("", "N/A")) %>%
  select(program_id, program_name = name)

mrs_patient_program <- sqlFetch(openmrs, "mrs_patient_program",
                                as.is = F,
                                stringsAsFactors = FALSE,
                                na.strings = c("", "N/A")) %>%
  filter(voided != 1) %>%                                        #filter out voided to avoid any entry mistakes
  select(patient_program_id,
         patient_id,
         program_id,
         date_enrolled,
         date_completed,
         voided)
#====write dataframes used====
dfs <- sapply(.GlobalEnv, is.data.frame) #list all dataframes
dfs <- dfs[dfs == T]

names(dfs)

lapply(mget(names(dfs)[dfs]), colnames)

mapply(write.csv, mget(names(dfs)[dfs]),
       file = paste0("F:/School/Tippie_Business Analytics/Health Care Analytics/Project/tables_used/",
                     names(dfs)[dfs], ".csv"),
       row.names = F, na = "")

#====data frames used====
dfs <- sapply(.GlobalEnv, is.data.frame)
dfs <- dfs[dfs == T]
data.frame(TablesUsed = names(dfs))

#=====encounter table====
df_encounter <- mrs_encounter %>%
  left_join(mrs_encounter_type %>%                #join encounter type
              select(-encounter_description),
            by = "encounter_type_id")

df_encounter %>%
  count(encounter_type_name) %>%                   #count the number of each `encounter_type`
  ggplot(aes(x = encounter_type_name, y = n)) +    #graphs the count of `encounter_type`
  geom_bar(stat = "identity") +                    #with a bar graph
  geom_text(aes(label = comma(n)),                 #add labels to the graph with a 1,000's comma
            position = position_dodge(0.9),
            vjust = -0.3) +
  ggtitle("Count of Encounter Types") +            #add title
  xlab("Encounter Type") +                         #ad axes titles
  ylab("Count of Encounters") + 
  scale_y_continuous(labels = comma) +             #set y-axis lables to with a 1,000's comma
  theme(plot.title = element_text(face = "bold"))  #set header to bold

count_patient_return <- df_encounter %>% count(patient_id, encounter_type_name)

data.frame(count_patient_return %>% filter(encounter_type_name == "ADULTINITIAL"))

data.frame(count_patient_return %>% filter(encounter_type_name == "ADULTINITIAL") %>%
             inner_join(count_patient_return,
                        by = "patient_id") %>%
             select(patient_id, encounter_type_name = encounter_type_name.y, n = n.y))



count_patient_return <- count_patient_return %>%
  filter(encounter_type_name != "ADULTRETURN" )

data.frame(count_patient_return %>%
             count(n) %>%
             rename(number_of_returns = n,
                    freq_patients_returning = nn))
#====program table====
df_program <- mrs_patient_program %>% 
  left_join(mrs_program,
            by = "program_id")

df_program_in <- df_program %>%
  count(patient_id, program_name) %>%
  spread(key = program_name, value = n) %>%
  mutate(program_in = ifelse(!is.na(`HIV Program`) & is.na(`TB Program`), "HIV Program",
                             ifelse(is.na(`HIV Program`) & !is.na(`TB Program`), "TB Program",
                                    ifelse(!is.na(`HIV Program`) & !is.na(`TB Program`), "Both Programs",
                                           "Review")))) %>%
  select(patient_id, program_in)

#how many people in each program
data.frame(df_program_in %>%
             count(program_in)) %>%
  mutate(freq = round(n/sum(n), 2)) %>%
  arrange(desc(n))

#====obs table====
df_obs <- mrs_obs %>%
  left_join(mrs_concept %>%
              select(concept_id, concept_name, short_name,
                     description, datatype, concept_class,
                     hi_absolute, hi_critical, hi_normal,
                     low_absolute, low_critical, low_normal,
                     units, precise),
            by = "concept_id") %>%
  left_join(., y = mrs_concept %>%
              select(concept_id,
                     ans_name = concept_name,
                     ans_description = description),
            by = c("value_coded" = "concept_id"))

#df_hiv
df_hiv <- df_obs %>%
  filter(grepl("CURRENT WHO HIV STAGE", concept_name, ignore.case = T) & !is.na(ans_name)) %>%
  select(encounter_id, patient_id, hiv_stage = ans_name) %>%
  distinct() %>%
  mutate(hiv_stage = as.integer(gsub("\\D", "", hiv_stage))) %>%
  distinct()

data.frame(head(df_hiv %>% count(patient_id, hiv_stage) %>% filter(n > 1)))
data.frame(head(df_hiv %>% count(encounter_id) %>% filter(n > 1)))
data.frame(df_hiv %>% filter(encounter_id == 6379))



#df_value
df_value <- df_obs %>%
  filter(datatype == "Numeric", value_numeric != 0) %>%
  select(encounter_id, patient_id, concept_name, description,
         ans_value = value_numeric) %>%
  mutate(concept_name = tolower(gsub(" ", "_",
                                     ifelse(grepl("CD3", concept_name),
                                            ifelse(grepl("(T-Suppressor or killer cells)", description), "killer_tcells",
                                                   ifelse(grepl("(T-helper cells)", description), "helper_tcells",
                                                          ifelse(grepl("Percentage of T-helper", description), "pct_helper_tcells",
                                                                 concept_name))), concept_name)))) %>%
  distinct()

df_value <- df_value %>%
  left_join(df_value %>% count(concept_name),
            by = "concept_name")  %>%
  filter(n > 1000) %>% select(-n) %>%
  mutate(concept_name = gsub("number_of_|\\(|\\)", "", concept_name))

df_value %>% group_by(concept_name) %>% tally()
data.frame(df_value %>% count(concept_name) %>% arrange(n))

df_value <- df_value %>%
  select(-description) %>%
  spread(key = concept_name, value = ans_value)

#df_rash
df_rash <- df_obs %>%
  filter(concept_class == "Finding" & ans_name == "RASH") %>%
  select(encounter_id, patient_id, rash = ans_name) %>%
  distinct()

#df_diagnosis
df_diagnosis <- df_obs %>%
  filter(concept_class == "Diagnosis") %>%
  select(encounter_id, patient_id, added_diagnosis = ans_name) %>%
  mutate(added_diagnosis = "Y") %>%
  distinct()

#df_tb
df_tb <- df_obs %>%
  filter(grepl("Current TB Treatment", concept_name, ignore.case = T), ans_name != "NONE") %>%
  select(patient_id, encounter_id, tb_treatement = ans_name) %>%
  mutate(tb_treatement = "Y") %>% distinct()

#df_test
df_test <- df_obs %>%
  filter(concept_class == "Test" & is.na(value_numeric) &
           concept_name != "IMMUNIZATIONS ORDERED" &
           ans_name != "INDETERMINATE") %>%
  mutate(concept_name = ifelse(grepl("HIV", concept_name), short_name, concept_name),
         concept_name = ifelse(grepl("SYPHILIS", concept_name), "SYPHILIS", concept_name),
         concept_name = tolower(gsub(" ", "_", concept_name))) %>%
  select(patient_id, encounter_id, concept_name, ans_name) %>%
  spread(key = concept_name, value = ans_name)

#====patient table====
df_patient <- mrs_patient %>% filter(is.na(country)) %>%
  left_join(mrs_tribe, by = "tribe_id") %>%
  select(-c(country, tribe_id))

df_patient %>%
  count(tribe_name) %>%                            #count the number of each `tribe_name`
  ggplot(aes(x = tribe_name, y = n)) +             #graphs the count of `tribe_name`
  geom_bar(stat = "identity") +                    #with a bar graph
  geom_text(aes(label = comma(n)),                 #add labels to the graph with a 1,000's comma
            position = position_dodge(0.9),
            vjust = -0.3) +
  ggtitle("Number of Patients in Each Tribe ") +   #add title
  xlab("Tribe Name") +                             #ad axes titles
  ylab("Count of Patients") + 
  scale_y_continuous(labels = comma) +             #set y-axis lables to with a 1,000's comma
  theme(plot.title = element_text(face = "bold"))  #set header to bold

#====combine info====
comb_df <- df_encounter %>%
  left_join(df_patient,
            by = "patient_id") %>%
  mutate(age = time_length(difftime(encounter_datetime, birthdate), "years")) %>%
  left_join(., df_program_in, by = "patient_id") %>%
  left_join(., df_hiv,
            by = c("encounter_id", "patient_id")) %>%
  left_join(., df_tb,
            by = c("encounter_id", "patient_id")) %>%
  left_join(., df_diagnosis,
            by = c("encounter_id", "patient_id")) %>%
  left_join(., df_rash,
            by = c("encounter_id", "patient_id")) %>%
  left_join(., df_test,
            by = c("encounter_id", "patient_id")) %>%
  left_join(., df_value,
            by = c("encounter_id", "patient_id")) %>%
  mutate(hiv_stage = ifelse(!is.na(hiv_stage), paste0("STAGE ", hiv_stage), hiv_stage)) %>%
  filter(encounter_type_name == "ADULTRETURN") %>%
  select(-encounter_type_id)

dup_check <- comb_df[duplicated(comb_df$encounter_id) | duplicated(comb_df$encounter_id, fromLast = T), ]

comb_df <- comb_df %>% filter(!duplicated(encounter_id) & !duplicated(comb_df$encounter_id, fromLast = T))

comb_df %>%
  filter(!is.na(killer_tcells) & !is.na(helper_tcells) & !is.na(hiv_stage)) %>%
  ggplot(aes(x = killer_tcells, y = helper_tcells, colour = hiv_stage)) +
  geom_point() +
  ggtitle("T-Cell Comparison at Different Stages of HIV") +  #add title
  xlab("Killer T-Cells") +                                   #ad axes titles
  ylab("Helper T-Cells") + 
  scale_y_continuous(labels = comma) +             #set y-axis lables to with a 1,000's comma
  scale_x_continuous(labels = comma) +
  theme(plot.title = element_text(face = "bold"))  #set header to bold

comb_df %>%
  filter(!is.na(killer_tcells) & !is.na(helper_tcells) & !is.na(hiv_stage) & helper_tcells >= 99) %>%
  ggplot(aes(x = killer_tcells, y = helper_tcells, colour = hiv_stage)) +
  geom_point() +
  facet_wrap( ~ hiv_stage, ncol = 2) +
  ggtitle("T-Cell Comparison at Different Stages of HIV") +  #add title
  xlab("Killer T-Cells") +                                   #ad axes titles
  ylab("Helper T-Cells") + 
  scale_y_continuous(labels = comma) +             #set y-axis lables to with a 1,000's comma
  scale_x_continuous(labels = comma) +
  theme(plot.title = element_text(face = "bold"))  #set header to bold

comb_df %>%
  mutate(other_diagnoses = ifelse(!is.na(tb_treatement) & !is.na(rash) & !is.na(added_diagnosis),
                                  "TB_RASH_ADDED", ifelse(!is.na(tb_treatement) & !is.na(rash) & is.na(added_diagnosis),
                                                          "TB_RASH", ifelse(!is.na(tb_treatement) & is.na(rash) & !is.na(added_diagnosis),
                                                                            "TB_ADDED", ifelse(is.na(tb_treatement) & !is.na(rash) & !is.na(added_diagnosis),
                                                                                               "RASH_OTHER",
                                                                                               ifelse(!is.na(tb_treatement),"TB",
                                                                                                      ifelse(!is.na(rash), "RASH",
                                                                                                             ifelse(!is.na(added_diagnosis), "ADDED", NA)))))))) %>%
  count(hiv_stage, other_diagnoses) %>%
  filter(!is.na(hiv_stage) & !is.na(other_diagnoses)) %>%
  ggplot(aes(x = hiv_stage, y = other_diagnoses, fill = n)) +
  geom_tile() +
  scale_fill_gradient(low = "pink", high = "red") +
  ggtitle("Other Diagnoses at Different HIV Stages") +  #add title
  xlab("HIV Stage") +                                   #ad axes titles
  ylab("Other Diagnoses Found") + 
  theme(plot.title = element_text(face = "bold"))  #set header to bold

comb_df %>%
  filter(!is.na(absolute_lymphocyte_count), !is.na(blood_platelet), !is.na(hiv_stage)) %>%
  ggplot(aes(x = absolute_lymphocyte_count, y = blood_platelet, colour = hiv_stage)) +
  geom_point() +
  facet_wrap( ~ hiv_stage) +
  scale_x_log10() +
  scale_y_log10()

nrow(comb_df %>% filter(!is.na(killer_tcells) & !is.na(helper_tcells) & !is.na(hiv_stage)))/nrow(comb_df)
nrow(comb_df %>% filter(!is.na(absolute_lymphocyte_count), !is.na(blood_platelet), !is.na(hiv_stage)))/nrow(comb_df)

write.csv(comb_df, "F:/School/Tippie_Business Analytics/Health Care Analytics/Project/comb_df.csv", row.names = F, na = "")
