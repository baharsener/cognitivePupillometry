
# Load packages
library(tidyverse); library(PupillometryR); library(here); library(dplyr); library(data.table); library(janitor); library(pracma); library(stringr); library(ggplot2); library(ggfittext); library(here); library(zoo); library(lme4); library(lmerTest); library(sjPlot)

# Code chunk Ariel wrote to make graphs look better than the default R version
theme_Publication <- function(base_size=18, base_family="Helvetica") {
  library(grid); library(ggthemes)
  (theme_foundation(base_size=base_size, base_family=base_family)
    + theme(plot.title = element_text(face = "bold",size = rel(1.2), hjust = 0.5),
            text = element_text(),panel.background = element_rect(colour = NA), plot.background = element_rect(colour = NA),
            panel.border = element_rect(colour = NA),axis.title = element_text(face = "bold",size = rel(1)),
            axis.title.y = element_text(angle=90,vjust =2),axis.title.x = element_text(vjust = -0.2),
            axis.text = element_text(), axis.line = element_line(colour="black"),axis.ticks = element_line(),
            panel.grid.major = element_blank(),panel.grid.minor = element_blank(),
            legend.position = "right", legend.direction = "vertical", legend.key.size= unit(0.8, "cm"),
            legend.title = element_text(face="bold"), legend.key = element_rect(colour = NA), plot.margin=unit(c(10,5,5,5),"mm"),
            strip.background=element_rect(colour="#f0f0f0",fill="#f0f0f0"),strip.text = element_text(face="bold")))
}

# Custom function to bind all columns of two dataframes, considers differences. 
rbind.all.columns <- function(x, y) {
  
  x.diff <- setdiff(colnames(x), colnames(y))
  y.diff <- setdiff(colnames(y), colnames(x))
  
  x[, c(as.character(y.diff))] <- NA
  
  y[, c(as.character(x.diff))] <- NA
  
  return(rbind(x, y))
}

# Function to format the participant_id id's from the behavioral data to match the format of the eyetracker data, this removes the date info
extract_id <- function(label) {
  id_part <- str_extract(label, "(?<=_)\\d+(?=_)") # Extract the numeric part
  return(as.numeric(id_part)) # Convert to numeric before returning
}

# A function to find the "origin" encoding trial number and trial direction for each retrieval image
find_origin_encoding_trials <- function(data) {
  # Initialize the columns
  data$originEncodingTrial <- NA
  data$originTrialDir <- NA
  
  # Go through each row to check against all triplet columns in the entire dataset
  for (i in seq_len(nrow(data))) {
    if (!is.na(data$retrievalImage[i])) {  # Only process retrieval trials
      img <- data$retrievalImage[i]
      
      # Check for matches in all of the values of the columns in that block
      matching_rows <- which(data$triplet1 == img | data$triplet2 == img | data$triplet3 == img)
      
      if (length(matching_rows) > 0) {
        # Grab the eTrials value for the first match
        data$originEncodingTrial[i] <- data$TRIAL_INDEX[matching_rows[1]]
        
        # Also grab the trialDirection of the matched encoding trial
        data$originTrialDir[i] <- data$trialDirection[matching_rows[1]]
      }
    }
  }
  
  return(data)
}
 

#1. Exclusion

###First excluding participants based on other factors such as not completing the task. Just checking the participant sheet to see if we made notes to exclude them. 

participants <- read.csv("ParticipantSheet.csv")
participants <- subset(participants, Exclude != "Yes" & TestDate != "")
 

###Next, for the rest of the participants, this chunk checks attention catch trials to make sure participant was actually doing the task, removing those who missed more than 2 same/different questions. 

filePath <- "Data/X"

filtered_file_list <- list.files(filePath, pattern = "\\.csv$", full.names = TRUE)

#Make a list of file names of the participants we think we should check for further exclusion
filtered_file_list <- filtered_file_list[
  unlist(sapply(filtered_file_list, function(x) {
    Participant_ID <- str_extract(x, "\\d+")
    Participant_ID %in% participants$Participant_ID
  }))
]

# Initialize an empty list to store valid file paths
valid_files <- c()
method_results <- list() #to store everyone's method accuracy

for (filename in filtered_file_list) {
  subFile <- here(filename) # Get file name/location
  subd <- read.csv(subFile) # Read in subject csv
  
  # Extract participant ID from the filename (assumes ID is part of the filename)
  participant_id <- str_extract(filename, "Participant[0-9]+")
  
  # Check accuracy using the methodCheck column
  subd <- subd %>%
    filter(trial_category == "encoding") %>%
    group_by(participant_id, TRIAL_INDEX) %>%
    summarize(attentionScore = mean(as.numeric(methodCheck), na.rm = TRUE)) %>%
    summarize(attentionScore = mean(attentionScore)) %>%
    mutate(
      attentionCheck = case_when(
        attentionScore >= 0.9 ~ "pass",
        attentionScore < 0.9 ~ "fail",
        TRUE ~ "check"
      ))
  # Add the results to the list
  method_results[[filename]] <- subd
  
  # Check if the participant passed the attention check
  if ("pass" %in% subd$attentionCheck) {
    valid_files <- c(valid_files, filename)
  }
}

# Make method results into dataframe
method_results <- do.call(rbind, method_results)
# Check which ones are with valid files
method_results <- method_results %>%
  filter(attentionCheck == "pass")
# Only include those who passed
filtered_file_list <- rownames(method_results)
 
#2. Sample data

###Import and clean raw data:

# Giant loop that was modified from WMC code and that has code from the PupillometryR tutorial
new_time_clean <- data.frame()
all_data <- data.frame()
all_missing <- data.frame()  

for (filename in filtered_file_list) {
  subFile <- here(filename) 
  subd <- read.csv(subFile)
  print(paste("Processing file:", filename, "with rows:", nrow(subd)))
  
  # Clean eye data
  subd <- subd %>% select(participant_id:TRIAL_START_TIME)  
  subd$LEFT_PUPIL_SIZE = as.numeric(as.character(subd$LEFT_PUPIL_SIZE)) 
  # Extract participant id
  subd$participant_id <- as.character(extract_id(subd$participant_id))
  subd <- subd %>% 
    filter(encodingType != "diff")  
  # I also want to get rid of trials for which participants did not answer the method (same/different) question correctly:
  subd <- subd %>% 
    filter(methodCheck != 0)
  
  # Set trial direction
  subd <- subd %>%
    mutate(trialDirection = case_when(
      trialType == "LMR" ~ "LR",
      trialType == "RML" ~ "RL",
      trialType == "RLM" ~ "NL",
      trialType == "LRM" ~ "NL",
      trialType == "MRL" ~ "NL",
      trialType == "MLR" ~ "NL",
      TRUE ~ NA
    ))
  
  subd_pup <- subd
  # Ensure 'message' column is not a list
  subd_pup$message <- unlist(subd_pup$message)
  
  # Put the data into pupillometryR format for further analysis:
  # Smooth/interpolate pupil data
  Sdata <- make_pupillometryr_data(data = subd_pup, subject = participant_id,
                                   trial = TRIAL_INDEX, time = TIMESTAMP, condition = trialDirection)
  
  # Downsampling
  mean_data <- downsample_time_data(data = Sdata,
                                    pupil = LEFT_PUPIL_SIZE,
                                    timebin_size = 50,
                                    option = 'median') # Calculating median pupil size in each timebin (ms)
  
  # Check what it looks like
  plot(mean_data, pupil = LEFT_PUPIL_SIZE, group = 'participant_id', main = "mean pupil dilation, downsampled")
  
  # Assessing how much missing data there is
  missing <- calculate_missing_data(mean_data, LEFT_PUPIL_SIZE) # what percentage is missing per trial.
  
  mean_data2 <- clean_missing_data(mean_data,
                                   pupil = LEFT_PUPIL_SIZE,
                                   trial_threshold = .50,
                                   subject_trial_threshold = .50)
  
  filtered_data <- filter_data(data = mean_data2,
                               pupil = LEFT_PUPIL_SIZE,
                               filter = 'median', 
                               degree = 11)
  
  # Interpolate across blinks
  int_data <- interpolate_data(data = filtered_data,
                               pupil = LEFT_PUPIL_SIZE,
                               type = 'linear') # fills gaps
  
  subd_pup$message <- subd_pup$SAMPLE_MESSAGE
  
  # Fill down for all timepoints with the messages
  subd_message <- subd_pup %>%
    mutate(message = as.character(message)) %>%
    mutate(newMessage = ifelse(message == ".", NA, message)) %>%
    fill(newMessage) %>%
    mutate(newMessage = as.factor(newMessage))
  
  #keep the first row for each bin
  subd_message_binned <- subd_message %>%
    mutate(TIMESTAMP = floor(TIMESTAMP / 50) * 50) %>%
    group_by(TIMESTAMP, participant_id, TRIAL_INDEX) %>%
    slice(1) %>%  #first row for each time bin
    ungroup()
  #enaming LEFT_PUPIL_SIZE here to know which df it comes from, this is not interpolated
  subd_message_binned <- subd_message_binned %>% 
    rename(RAW_PUPIL_SIZE = LEFT_PUPIL_SIZE)
  
  # Merging the filtered and interpolated data with the data that is labelled well
  #I also want to bring triplet images displayed in blocks one and two under the same column
  sub_merged <- merge(int_data, subd_message_binned, by = c("participant_id", "TRIAL_INDEX", "TIMESTAMP"), all = TRUE) %>%
    filter(Timebin > 0) %>%
    group_by(TRIAL_INDEX) %>%
    fill(newMessage, .direction = "downup") %>%
    mutate(
      triplet1 = case_when(
        trial_category == "encoding" & triplet1_1 %in% c(".", "UNDEFINED") ~ triplet1_2,
        trial_category == "encoding" ~ triplet1_1,
        TRUE ~ NA_character_ # For non-encoding trials, leave as NA
      ),
      triplet2 = case_when(
        trial_category == "encoding" & triplet2_1 %in% c(".", "UNDEFINED") ~ triplet2_2,
        trial_category == "encoding" ~ triplet2_1,
        TRUE ~ NA_character_
      ),
      triplet3 = case_when(
        trial_category == "encoding" & triplet3_1 %in% c(".", "UNDEFINED") ~ triplet3_2,
        trial_category == "encoding" ~ triplet3_1,
        TRUE ~ NA_character_
      )
    ) %>%
    select(participant_id, TIMESTAMP, Timebin, TRIAL_INDEX, triplet1, triplet2, triplet3, newMessage, orderPosition, LEFT_PUPIL_SIZE, LEFT_GAZE_X, LEFT_GAZE_Y, trialDirection.x, trial_category, trialType, eTrials, retTrials, decisionMade, encoding_order, retrievalImage) %>%
    rename(trialDirection = trialDirection.x)
  # We drop NA in the line after this, but that removes ret trials as well. To prevent this, I am renaming the trial direction column NA's
  sub_merged <- sub_merged %>% 
    mutate(trialDirection = ifelse(is.na(trialDirection), ".", as.character(trialDirection)))
  
  # Making 'decision made' numeric to calculate timestamps for retrieval decision time
  sub_merged$decisionMade <- as.numeric(sub_merged$decisionMade)
  
  # Resetting the timestamp at the beginning of each trial again 
  subd_sub_merged <- sub_merged %>%
    filter(TRIAL_INDEX > 0) %>%
    drop_na(LEFT_PUPIL_SIZE, TRIAL_INDEX, TIMESTAMP) %>%  #drop rows with NA for important columns
    droplevels() %>%
    arrange(TIMESTAMP)
  unique_trials <- unique(subd_sub_merged$TRIAL_INDEX)
  
  for (trial in unique_trials) {
    this_trial <- subd_sub_merged %>% filter(TRIAL_INDEX == trial)
    print(paste("Processing trial:", trial))
    start_trial <- this_trial$TIMESTAMP[1] #get first timestamp per trial
    this_trial$new_time <- this_trial$TIMESTAMP - start_trial
    
    # Calculate decision_time if it's a retrieval trial
    if (this_trial$trial_category[1] == "retrieval" && !is.na(this_trial$decisionMade[1])) {
      this_trial$decision_time <- floor((this_trial$decisionMade - start_trial) / 50) * 50 #decision time, but rounding it to the nearest 50 ms!
    } else if (this_trial$trial_category[1] == "retrieval") {
      this_trial$decision_time <- NA  #retrieval trial without decisionMade
    }
    # Combine the trials
    if (trial == unique_trials[1]) {
      new_time_clean <- this_trial
    } else {
      new_time_clean <- rbind(new_time_clean, this_trial)
    }
  }
  
  # Merge data for all subjects together
  if (filename == filtered_file_list[1]) {
    all_data <- new_time_clean
    all_missing <- missing
  } else {
    all_data <- rbind(all_data, new_time_clean)
    all_missing <- rbind(all_missing, missing)
  }
}

# Now I want to "flag" the pre-decision phase using the decision_time column (which is why I rounded it down)
all_data <- all_data %>%
  group_by(participant_id, TRIAL_INDEX) %>%
  mutate(
    preDecision = case_when(
      # Mark the current row as 'Decision' when it matches new_time
      !is.na(new_time) & !is.na(decision_time) & (new_time == decision_time) ~ "Decision",
      # Check the rows two time bins before (100 ms before the decision), mark as pre-decision
      row_number() == (which(new_time == decision_time)[1] - 2) ~ "Pre-decision",
      row_number() == (which(new_time == decision_time)[1] - 1) ~ "Pre-decision",
      TRUE ~ NA_character_ 
    ),
    block = ifelse(TRIAL_INDEX < 46, 1, 2)) %>% #add in block information
  ungroup()

# Check participant id's
unique(all_data$participant_id)

# Clean up participant response
all_data$orderPosition <- str_extract(all_data$orderPosition, "[a-zA-Z]+")

# Take a look
summary(all_data)

# Renaming variables
all_data <- rename(all_data, trialOrder = trialType, orderResponse = orderPosition)

# Check how many trials were removed due to missing data
missing_threshold <- all_missing %>%
  na.exclude(all_missing) %>%
  mutate(trial_type = case_when(
    TRIAL_INDEX >= 1 & TRIAL_INDEX < 26 ~ "encoding",
    TRIAL_INDEX > 45 & TRIAL_INDEX < 71 ~ "encoding",
    TRUE ~ "retrieval"
  )) %>%
  filter(Missing > 0.5) %>%
  group_by(trial_type) %>%
  summarize(count = n(), .groups = 'drop')

missing_by_subj <- all_missing %>%
  na.exclude(all_missing) %>%
  mutate(trial_type = case_when(
    TRIAL_INDEX >= 1 & TRIAL_INDEX < 26 ~ "encoding",
    TRIAL_INDEX > 45 & TRIAL_INDEX < 71 ~ "encoding",
    TRUE ~ "retrieval"
  )) %>%
  filter(Missing > 0.5) %>%
  group_by(participant_id, trial_type) %>%
  summarize(count = n(), .groups = 'drop')
 

#3. Fixation data
###Import and clean fixation data

# Import and clean fixation data
all_fixation <- data.frame()
filePath <- "Data/testFixation"
filtered_file_list <- list.files(filePath, pattern = "\\.csv$", full.names = TRUE)

# Combine fixation reports
filtered_file_list <- filtered_file_list[
  unlist(sapply(filtered_file_list, function(x) {
    Participant_ID <- str_extract(x, "\\d+")
    Participant_ID %in% participants$Participant_ID
  }))
]

for (filename in filtered_file_list) {
  subFile <- here(filename) # get file name/location
  fixation <- read.csv(subFile) # read in subject csv
  
  fixation <- fixation %>% 
    filter(encodingType != "diff", methodCheck != 0) # remove diff trials, and trials for which methodCheck was incorrect
  
  # Set trial direction 
  fixation <- fixation %>%
    mutate(trialDirection = case_when(
      trialType == "LMR" ~ "LR",
      trialType == "RML" ~ "RL",
      trialType == "RLM" ~ "NL",
      trialType == "LRM" ~ "NL",
      trialType == "MRL" ~ "NL",
      trialType == "MLR" ~ "NL",
      TRUE ~ NA 
    ))
  
  # Put triplet info under one column each
  sub_fix_clean <- fixation %>% 
    mutate(
      triplet1 = case_when(
        trial_category == "encoding" & triplet1_1 %in% c(".", "UNDEFINEDnull") ~ triplet1_2,
        trial_category == "encoding" ~ triplet1_1,
        TRUE ~ NA_character_ # For non-encoding trials, leave as NA
      ),
      triplet2 = case_when(
        trial_category == "encoding" & triplet2_1 %in% c(".", "UNDEFINEDnull") ~ triplet2_2,
        trial_category == "encoding" ~ triplet2_1,
        TRUE ~ NA_character_
      ),
      triplet3 = case_when(
        trial_category == "encoding" & triplet3_1 %in% c(".", "UNDEFINEDnull") ~ triplet3_2,
        trial_category == "encoding" ~ triplet3_1,
        TRUE ~ NA_character_
      )) %>%
    select(c(participant_id, TRIAL_INDEX, eTrials, retTrials, trial_category, triplet1, triplet2, triplet3, CURRENT_FIX_START, CURRENT_FIX_DURATION, CURRENT_FIX_X, CURRENT_FIX_Y, CURRENT_FIX_PUPIL, TRIAL_START_TIME, CURRENT_FIX_MSG_TEXT_1, trialType, trialDirection, retrievalImage, encoding_order, orderPosition))
  
  #Merge data for all subjects together
  if (filename == filtered_file_list[1]) {
    all_fixation <- sub_fix_clean
  } else {
    all_fixation <- rbind(all_fixation, sub_fix_clean)
  }
}

# Extract participant id's
all_fixation$participant_id <- str_extract(all_fixation$participant_id, "\\d+")
unique(all_fixation$participant_id)

# Put in block information
all_fixation <- all_fixation %>%
  group_by(participant_id, TRIAL_INDEX) %>%
  mutate(block = ifelse(TRIAL_INDEX < 46, 1, 2))

# Remove unnecessary characters from the participant responses for later comparison
all_fixation$orderPosition <- str_extract(all_fixation$orderPosition, "[a-zA-Z]+")

# Remove outlier fixations, keeping only the ones between 150 and 1000 ms 
all_fixation <- all_fixation %>%
  filter(CURRENT_FIX_DURATION < 1001, CURRENT_FIX_DURATION > 149)

# Mark 'anchor' fixation (right before the image disappears) and the first fixation after that
all_fixation <- all_fixation %>%
  group_by(participant_id, TRIAL_INDEX) %>% # Group by participant and trial
  arrange(CURRENT_FIX_START) %>%   
  mutate(ret_fix = case_when(
    trial_category == "retrieval" & CURRENT_FIX_START < 3500 & lead(CURRENT_FIX_START, default = NA_integer_) >= 3500 ~ "anchor", 
    trial_category == "retrieval" & lag(CURRENT_FIX_START < 3500, default = FALSE) & CURRENT_FIX_START >= 3500 ~ "after_anchor", 
  ) 
  ) %>%
  ungroup()

# Rename to match all_data
all_fixation <- rename(all_fixation, orderResponse = orderPosition)

# Take a look
summary(all_fixation)
 

#4. Behavioral data
###Shape behavioral data for analysis

# Fixation data doesn't have removals due to missing eye data, so using that for behavioral accuracy
all_fixation <- read.csv("Analysis/allFixation.csv", row.names = 1)

# Get encoding position for each retrieval image
recall_data <- beh_data %>%
  group_by(participant_id) %>%
  mutate(
    # Loop through each row and find the matching retrieval image in the triplet columns
    encoding_position = purrr::map2_chr(retrievalImage, trialType, function(retrieval_img, trial_type) {
      match_found <- NA_character_
      # Check for non-missing retrieval image and triplet columns
      if (!is.na(retrieval_img) && retrieval_img != "UNDEFINEDnull" && retrieval_img != ".") {
        for (i in 1:n()) {  # Iterate through all rows for the participant
          # Check if retrieval image matches any of the triplet values
          if (retrieval_img %in% c(cur_data()$triplet1[i], cur_data()$triplet2[i], cur_data()$triplet3[i])) {
            match_found <- cur_data()$trialType[i]
            break
          }
        }
      }
      match_found  
    })
  ) %>%
  ungroup()

# But this only manages to get the whole trialType, not the individual letters so I have to mutate once more
recall_data <- recall_data %>%
  mutate(encoding_position = 
           case_when(
             encoding_order == "first" ~ substr(encoding_position, 1, 1),
             encoding_order == "second" ~ substr(encoding_position, 2, 2),
             encoding_order == "third" ~ substr(encoding_position, 3, 3)))

# Now get the original trial number and direction
# Use the function we defined in setup to find 'origin' encoding trial numbers and direction for each retrieval image: split by participant and block to apply the function
participants_block <- split(recall_data, list(recall_data$participant_id, recall_data$block))

updated_data <- lapply(participants_block, find_origin_encoding_trials)

# Merge it back together
recall_data_full <- do.call(rbind, updated_data)

# Get rid of NA's 
recall_data_full <- recall_data_full[!is.na(recall_data_full$TRIAL_INDEX), ]

# Make new df with clean retrieval data, with retrieval accuracy
all_recall_clean <- recall_data_full %>%
  filter(trial_category == "retrieval", !is.na(originTrialDir)) %>% #remove if encoding info is missing
  mutate(is_correct = 
           if_else(encoding_order == orderResponse, 1, 0))
 
