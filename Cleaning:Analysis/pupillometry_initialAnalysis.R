
# Load packages
library(tidyverse); library(PupillometryR); library(here); library(dplyr); library(data.table); library(janitor); library(pracma); library(stringr); library(ggplot2); library(ggfittext); library(here); library(zoo); library(lme4); library(lmerTest); library(sjPlot); library(caret); library(ISLR); library(nnet)

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


# For bootstrapping 95% confidence intervals -- from Mike Frank https://github.com/langcog/KTE/blob/master/mcf.useful.R
library(bootstrap)
theta <- function(x,xdata,na.rm=T) {mean(xdata[x],na.rm=na.rm)}
ci.low <- function(x,na.rm=T) {
  quantile(bootstrap(1:length(x),1000,theta,x,na.rm=na.rm)$thetastar,.025,na.rm=na.rm)} 
ci.high <- function(x,na.rm=T) {
  quantile(bootstrap(1:length(x),1000,theta,x,na.rm=na.rm)$thetastar,.975,na.rm=na.rm) } 


#1. Recall analysis
Trial balancing
Confirm that trial direction at encoding, and order/position balancing at retrieval work well

all_data <- read.csv("Analysis/allData.csv", row.names = 1)
all_recall_clean <- read.csv("Analysis/all_recall_clean.csv", row.names = 1)

# Data types change again after reading in the csv, so make sure to make the changes after you load them. 
#all_data
all_data <- all_data %>%
  mutate(across(
    c(orderResponse, trialDirection, trial_category, trialOrder, block, encoding_order, preDecision),
    as.factor))


#all_recall_clean
all_recall_clean <- all_recall_clean %>%
  mutate(across(
    c(encoding_order, encoding_position, orderResponse, block, originTrialDir),
    as.factor))

# Dataframe for the encoding phase: I'm cutting timestamps longer than 15 seconds (this is when the attention question appears, so I will mark this as the end of the encoding phase with a half second buffer)
encoding_phase <- all_data %>%
  filter(trial_category == "encoding",
         new_time < 15050)

# Dataframe for the retrival phase
retrieval_phase <- all_data %>%
  filter(trial_category == "retrieval")

# Check what encoding trials look like:
encTrials <- encoding_phase %>%
  group_by(participant_id, TRIAL_INDEX) %>%
  summarize(trialDirection = first(trialDirection), .groups = 'drop') %>%
  arrange(participant_id, TRIAL_INDEX)

# Check encoding trial order balancing
enc_trialCounts <- encTrials %>%
  group_by(participant_id, trialDirection) %>%
  summarize(trial_count = n(), .groups = 'drop') %>%
  arrange(participant_id, trialDirection) %>%
  filter(trialDirection != ".")

enc_trialTot <- enc_trialCounts %>%
  group_by(trialDirection) %>%
  summarize(tot = sum(trial_count))

#Check order/position balancing: 
ret_trialCounts <- all_recall_clean %>%
  group_by(participant_id, encoding_order, encoding_position) %>%
  summarize(trial_count = n(), .groups = 'drop') %>%
  arrange(participant_id, encoding_order) %>%
  filter(encoding_order != ".")

ret_trialTot <- all_recall_clean %>%
  group_by(encoding_order, encoding_position) %>%
  summarize(tot = sum(trial_count = n()))

# How many ret trials per participant?
ret_trialSubj <- all_recall_clean %>%
  group_by(participant_id) %>%
  summarize(trial_count = n(), .groups = 'drop')

###Calculate and visualize memory accuracy by trial direction, across both blocks and separated by blocks

# Subject-level accuracy for retrieval trials, grouped by direction
ret_acc_sub <- all_recall_clean %>%
  group_by(participant_id, originTrialDir) %>%
  summarise(acc = mean(is_correct)) %>%
  mutate(originTrialDir = as.factor(originTrialDir))

# Group-level accuracy for retrieval trials, grouped by direction
ret_acc_group <- all_recall_clean %>%
  group_by(originTrialDir) %>%
  summarize(accuracy = mean(is_correct), n = length(originTrialDir), hi = ci.high(is_correct), low = ci.low(is_correct))

# Visalize behavioral accuracy, subject:
ggplot(data = ret_acc_sub, aes(x = originTrialDir, y = acc)) + geom_boxplot(aes(group = trialDirection)) + scale_x_discrete(labels = c("LR", "NL", "RL"))

# Visualize behavioral accuracy, group:
ret_acc_group$Condition <- "temporal"
ggplot(data = ret_acc_group, aes(x = originTrialDir, y = accuracy, group=Condition)) + geom_line(aes(linetype=factor(Condition)), show.legend = F) + geom_point() + 
  geom_errorbar(aes(max=hi, min=low), width=.2) + ylim(0,1) +
  geom_hline(yintercept = .33, linetype="dashed", alpha=.5) +
  scale_x_discrete(labels = c("LR", "NL", "RL")) + theme_Publication() + ylab("Accuracy") +xlab("Orientation") + theme_Publication()

# Are there differences in accuracy by trial blocks?
# Subject-level accuracy for retrieval trials, grouped by trial direction and block
ret_acc_block <- all_recall_clean %>%
  group_by(participant_id, originTrialDir, block) %>%
  summarise(acc = mean(is_correct)) %>%
  mutate(trialDirection = as.factor(originTrialDir))

# Stat check for main effect of trial direction on accuracy
ACC_recall <- glmer(is_correct ~ originTrialDir + (1 | participant_id), family = binomial(link = "logit"), control=glmerControl(optimizer="bobyqa"), data = all_recall_clean)
summary(ACC_recall)

# Look at block as well:
ACC_recall_block <- glmer(is_correct ~ originTrialDir + block + (1 | participant_id), family = binomial(link = "logit"), control=glmerControl(optimizer="bobyqa"), data = all_recall_clean)
summary(ACC_recall_block)
 

###Mistakes people are making by order/position, across both blocks and separated by blocks

# Add mistake categories to all_recall_clean
all_recall_clean <- all_recall_clean %>%
  mutate(
    mistake_type = case_when(
      encoding_order == "first" & orderResponse == "second" ~ "first->second",
      encoding_order == "first" & orderResponse == "third" ~ "first->third",
      encoding_order == "second" & orderResponse == "first" ~ "second->first",
      encoding_order == "second" & orderResponse == "third" ~ "second->third",
      encoding_order == "third" & orderResponse == "first" ~ "third->first",
      encoding_order == "third" & orderResponse == "second" ~ "third->second",
      TRUE ~ "correct"
    ))

# Create a  table of mistakes (correct answer vs. recall answer)
mistakes_dir <- ftable(all_recall_clean$originTrialDir, 
                       all_recall_clean$encoding_order, 
                       all_recall_clean$orderResponse)

# Summary of mistakes made, using count because not all order/positions are represented equally 
# Summarize mistakes with proportions, for each subject, for both blocks:
mistake_sub <- all_recall_clean %>%
  filter(is_correct == 0) %>% 
  group_by(participant_id, originTrialDir, encoding_position, encoding_order) %>%
  mutate(total_trials = n()) %>%
  group_by(participant_id, originTrialDir, encoding_position, encoding_order, mistake_type) %>%
  summarise(
    count = n(),
    total_trials = first(total_trials), # tot trials for pos/order pair
    .groups = "drop"
  )

# Summarize mistakes with proportions, group-level, for both blocks:
mistake_group <- all_recall_clean %>%
  filter(is_correct == 0) %>% 
  group_by(originTrialDir, encoding_position, encoding_order) %>%
  mutate(total_trials = n()) %>%
  group_by(originTrialDir, encoding_position, encoding_order, mistake_type) %>%
  summarise(
    count = n(),
    total_trials = first(total_trials), # tot trials for pos/order pair
    .groups = "drop"
  )

# Visualize mistakes/prop correct by order and position, across both blocks
ggplot(mistake_group %>% filter(mistake_type != "correct"),
       aes(x = interaction(encoding_position, encoding_order), 
           y = count, fill = mistake_type)) + scale_fill_manual(values = c("#cc2224", "#2daa01","#ff9328","#ef5bf4","#3c5fee","#019e99")) +
  geom_bar(stat = "identity", position = "stack") +
  labs(
    x = "Encoding Position and Order", 
    y = "Count", 
    title = "Proportion of Mistakes by Trial Direction and Encoding Position/Order"
  ) + 
  theme(axis.text.x = element_text(angle = 45, hjust = 1))



#2. Pupil dilation.
###Encoding Baseline

# Calculate baseline pupil dilation using the last 100 ms of fixation
enc_baseline_pup_data = encoding_phase %>%
  filter(new_time >= 1900 & new_time < 2000) %>% #last 100 ms of the fixation period is 2 timebins
  group_by(participant_id, TRIAL_INDEX) %>%
  summarise(base_pup = mean(LEFT_PUPIL_SIZE)) 

# Plot it
ggplot(enc_baseline_pup_data, aes(x=TRIAL_INDEX, y = base_pup)) + geom_point() + facet_wrap(~participant_id) 

# Do any trials have a bad baseline and need to be cut? Look at zscores:
enc_baseline_zscores <- enc_baseline_pup_data %>%
  group_by(participant_id) %>%
  mutate(zbase_pup = c(scale(base_pup, center = T, scale = T)))

# Join with full dataframe
enc_data_relative <- full_join(encoding_phase, enc_baseline_zscores)

# I want to remove outlier zscores while keeping track of how many trials are being cut
cut_baseline_trials <- tibble()

cut_enc <- enc_data_relative %>%
  filter(!between(zbase_pup, -1.95, 1.95)) %>%
  distinct(participant_id, TRIAL_INDEX)

# Remove outlier baseline values
enc_data_relative <- enc_data_relative %>%
  filter(between(zbase_pup,-1.95,1.95)) %>%
  mutate(rel_pup = (LEFT_PUPIL_SIZE-base_pup))

summary(enc_data_relative)

# Visualize relative pupil dilation over the encoding trial after the fixation and before the method question
ggplot(enc_data_relative %>% filter(new_time > 2000, new_time < 15000), aes(x=new_time, y = rel_pup, color = as.factor(trialDirection))) + geom_point() + facet_wrap(~participant_id) 

# Mean relative pupil dilation (not per trial), over time
avg_enc_rel_data <- enc_data_relative %>%
  group_by(new_time, trialDirection, participant_id) %>%
  summarise(mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

# Visualize pupil dilation per trial direction per participant
ggplot(avg_enc_rel_data %>% filter(new_time > 2000, new_time < 7500), aes(x=new_time, y = mean_pup, color = as.factor(trialDirection))) + geom_point() + facet_wrap(~participant_id)

# Visualize group-level averaged data, not per trial, over time
enc_group_avg_rel <- avg_enc_rel_data %>%
  group_by(trialDirection, new_time) %>%
  summarise(pupil = mean(mean_pup))

summary(enc_group_avg_rel)

#Plot of pupil dilation during the encoding trial, across both blocks, grouped across participants
#Pink-purple colors are triplet images and yellow is mask
ggplot(data= enc_group_avg_rel,
       aes(x=new_time, y = pupil, colour=as.factor(trialDirection))) + 
  geom_line() + geom_point() + facet_wrap(~trialDirection) + 
  annotate("rect", xmin=1800, xmax=2000, ymin=-Inf, ymax=Inf, alpha=0.2, fill="yellow") +
  annotate("text", x=1200, y=150 , label = "Fixation", size = 2) +
  annotate("rect", xmin=2000, xmax=3500, ymin=-Inf, ymax=Inf, alpha=0.2, fill="blueviolet") +
  annotate("text", x=2750, y=150 , label = "Triplet 1", size = 2) + 
  annotate("rect", xmin=4000, xmax=5500, ymin=-Inf, ymax=Inf, alpha=0.2, fill="darkmagenta") +
  annotate("text", x=4750, y=150 , label = "Triplet 2", size = 2) + 
  annotate("rect", xmin=6000, xmax=7500, ymin=-Inf, ymax=Inf, alpha=0.2, fill="deeppink1") +
  annotate("text", x=6750, y=150 , label = "Triplet 3", size = 2) +
  ylab("Relative pupil dilation") + xlab("Time") + labs(colour = "Trial Direction") + ggtitle("Relative Pupil Dilation Over a Trial by Trial Direction") +theme_Publication() + xlim(1800,7600)
 

###Dilation by trial direction

#Subject-level mean and max pupil dilation by trial direction and block
sub_enc_pup_trialdir <- enc_data_relative %>%
  group_by(trialDirection, participant_id, block) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

#Visualize mean pupil dilation
ggplot(data = sub_enc_pup_trialdir, aes(x = trialDirection, y = mean_pup, group = interaction(participant_id, block), 
                                        colour = as.factor(trialDirection))) + geom_point(size = 3) + geom_line() + facet_grid(block ~ participant_id) + xlab("Trial Direction") + ylab("Mean Pupil Dilation") + ggtitle("Mean Relative Pupil Dilation by Trial Direction") + theme_Publication()

#Visualize max pupil dilation
ggplot(data = sub_enc_pup_trialdir, aes(x = trialDirection, y = max_pup, group = interaction(participant_id, block), 
                                        colour = as.factor(trialDirection))) + geom_point(size = 3) + geom_line() + facet_grid(block ~ participant_id) + xlab("Trial Direction") + ylab("Maximum Pupil Dilation") + ggtitle("Max Relative Pupil Dilation by Trial Direction") + theme_Publication()


#Group-level mean and max pupil dilation by trial direction and block
group_enc_pup_trialdir <- enc_data_relative %>%
  group_by(trialDirection, block) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

#Visualize mean pupil dilation
ggplot(data = group_enc_pup_trialdir, aes(x = trialDirection, y = mean_pup, group = block, colour = as.factor(trialDirection))) + geom_point(size = 3) + geom_line() + facet_wrap(~block) + xlab("Trial Direction") + ylab("Mean Pupil Dilation") + ggtitle("Mean Relative Pupil Dilation by Trial Direction") + theme_Publication()

#Visualize max pupil dilation
ggplot(data = group_enc_pup_trialdir, aes(x = trialDirection, y = max_pup, group = block, colour = as.factor(trialDirection))) + geom_point(size = 3) + geom_line() + facet_wrap(~block) + xlab("Trial Direction") + ylab("Maximum Pupil Dilation") + ggtitle("Max Relative Pupil Dilation by Trial Direction") + theme_Publication()
 

###Stats: Trial Direction X Encoding Pupil Dilation

# 1. Mean pupil dilation by trial direction
rel_pup_dir_model <- lmer(rel_pup ~ trialDirection + (1 | participant_id), data = enc_data_relative)
summary(rel_pup_dir_model)

#I put the whole data here, not mean or max!
encoding_pupil <- enc_data_relative %>%
  group_by(participant_id, TRIAL_INDEX, trialDirection, block) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

# 2. Mean pupil dilation by trial direction
mean_pup_dir_model <- lmer(mean_pup ~ trialDirection + (1 | participant_id), data = encoding_pupil)
summary(mean_pup_dir_model)

# 3. Maximum pupil dilation by trial direction
max_pup_dir_model <- lmer(max_pup ~ trialDirection (1 | participant_id), data = encoding_pupil)
summary(max_pup_dir_model)
 

###Dilation at encoding by retrieval accuracy
#Manipulate pupil df to merge with behavioral data (include trial info)
enc_pup_tomerge <- enc_data_relative %>%
  group_by(TRIAL_INDEX, trialDirection, participant_id, block) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

# Now I have to manipulate the recall dataframe to be able to merge with the dilation data: renaming originEncodingTrial to TRIAL_INDEX to merge using that (bc the trial index here in this df is the index of the retrieval trial)
recall_tomerge <- all_recall_clean %>%
  select(-c(TRIAL_INDEX)) %>%
  rename(TRIAL_INDEX = originEncodingTrial)

pupil_acc_encoding <- enc_pup_tomerge %>%
  left_join(recall_tomerge, by = c("participant_id", "TRIAL_INDEX"))

pupil_acc_encoding$participant_id <- as.factor(pupil_acc_encoding$participant_id)

pupil_acc_encoding <- pupil_acc_encoding %>%
  filter(!is.na(retrievalImage)) %>%
  select(-c(block.y)) %>%
  rename(block = block.x)

# Sanity check, print rows where trial direction and origin trial direction columns do not match
pupil_acc_encoding[pupil_acc_encoding$trialDirection != pupil_acc_encoding$originTrialDir, ]
 

###Stats: Trial Direction X Encoding Pupil Dilation x Accuracy
# These models account for position in sequence here as well: if there is an overall greater dilation for the third item, we would want to include that in the model.

# 1. Does mean dilation during encoding predict accuracy?
acc_by_mean_dilation <- glmer(is_correct ~ mean_pup + encoding_position + (1|participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_encoding)
summary(acc_by_mean_dilation)

# Visualize it
plot_model(acc_by_mean_dilation, type = "pred")
# For now, seems to not have an influence. 

# 2. Does maximum dilation during encoding predict accuracy?
acc_by_max_dilation <- glmer(is_correct ~ max_pup + encoding_position + (1|participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_encoding)
summary(acc_by_max_dilation)

# Visualize it
plot_model(acc_by_max_dilation, type = "pred")

# 3. Does mean dilation during encoding interact with trial direction and accuracy?
acc_by_dir_mean <- glmer(is_correct ~ trialDirection * mean_pup + encoding_position + (1|participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_encoding)
summary(acc_by_dir_mean)

# Visualize it
plot_model(acc_by_dir_mean, type = "int")

# 4. Does maximum dilation during encoding interact with trial direction and accuracy?
acc_by_dir_max <- glmer(is_correct ~ trialDirection * max_pup + encoding_position + (1| participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_encoding)
summary(acc_by_dir_max)

# Visualize it
plot_model(acc_by_dir_max, type = "int")
 

###Retrieval Baseline

ret_baseline_pup_data <- retrieval_phase %>% 
  filter(new_time >= 1900, new_time < 2050) %>% # last 100 ms of fixation
  group_by(participant_id, TRIAL_INDEX) %>%
  summarise(base_pup = mean(LEFT_PUPIL_SIZE))

# Visualize it
ggplot(ret_baseline_pup_data, aes(x=TRIAL_INDEX, y = base_pup)) + geom_point() + facet_wrap(~participant_id)

# Get baseline zscores to remove outliers
ret_baseline_zscores <- ret_baseline_pup_data %>%
  group_by(participant_id) %>%
  mutate(zbase_pup = c(scale(base_pup, center = T, scale = T)))

ret_data_relative <- full_join(retrieval_phase, ret_baseline_zscores)

# I again want to keep track of how many trials are being cut
cut_ret <- ret_data_relative %>%
  filter(!between(zbase_pup, -1.95, 1.95)) %>%
  distinct(participant_id, TRIAL_INDEX)

cut_baseline_trials <- bind_rows(cut_baseline_trials, cut_ret)

# Remove outlier baselines
ret_data_relative <- ret_data_relative %>%
  filter(between(zbase_pup,-1.95,1.95)) %>%
  mutate(rel_pup = (LEFT_PUPIL_SIZE-base_pup))

# Print summary of the processed data
summary(ret_data_relative)

#Let's see what it looks like after ret image + ret question per participant
ret_data_average <- ret_data_relative %>%
  group_by(participant_id, new_time) %>%
  summarise(pupil = mean(rel_pup))

# Plotting pupil dilation for the the whole duration (until answer options)
ggplot(ret_data_average %>% filter(new_time < 4500) , aes(x=new_time, y = pupil)) + geom_point() + geom_line() + facet_wrap(~participant_id)


# Make timestamp column relative to when a decision is made
retDecision <- ret_data_relative %>%
  group_by(participant_id, TRIAL_INDEX) %>%
  mutate(
    decision_timestamp = min(new_time[preDecision == "Decision"], na.rm = TRUE),
    relative_time = new_time - decision_timestamp
  ) %>%
  ungroup()

summary(retDecision)

# Make 'time period' into factor for visualization
retDecision$preDecision <- as.factor(retDecision$preDecision)

# Look at a longer time period, to include some of the decision part. 
ggplot(retDecision, aes(x=relative_time, y = rel_pup,  color = preDecision)) + geom_point() + geom_line() + facet_wrap(~participant_id) + ylab("Relative pupil dilation") + xlim(c(-150, 150)) + xlab("Time") + ggtitle("Average Relative Pupil Dilation Over Retrieval Trials") + theme_Publication()


# Getting group- level mean relative pupil dilation
ret_avg_rel_data <- ret_data_relative %>%
  group_by(new_time, retTrials, participant_id) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

# Getting group-level mean relative pupil dilation with decision information
dec_rel_data = retDecision %>%
  group_by(relative_time, participant_id) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()
 

### Dilation at retrieval and retrieval accuracy

#Mean and max pupil for each trial (no time information)
ret_pup_tomerge <- ret_data_relative %>%
  group_by(TRIAL_INDEX, retTrials, participant_id) %>%
  summarise(max_pup = max(rel_pup), mean_pup = mean(rel_pup), pup_sd = sd(rel_pup), pup_length = length(rel_pup), 
            pup_sem = pup_sd/sqrt(pup_length), 
            upper_CI = mean_pup + qt(1 - (0.05 / 2), pup_length - 1) * pup_sem,
            lower_CI = mean_pup - qt(1 - (0.05 / 2), pup_length - 1) * pup_sem) %>%
  drop_na()

pupil_acc_retrieval <- ret_pup_tomerge %>%
  left_join(all_recall_clean, by = c("participant_id", "TRIAL_INDEX"))

pupil_acc_retrieval <- pupil_acc_retrieval %>%
  filter(!is.na(retrievalImage)) %>%
  select(-c(retTrials.y)) %>%
  rename(retTrials = retTrials.x)

pupil_acc_retrieval$participant_id <-  as.factor(pupil_acc_retrieval$participant_id)
 
###Stats: Trial Direction X Retrieval Pupil Dilation

# 1. Mean retrieval pupil dilation by encoding trial direction
ret_mean_dir_model <- lmer(mean_pup ~ originTrialDir + (1|participant_id), data = pupil_acc_retrieval)
summary(ret_mean_dir_model)

# 2. Maximum retrieval pupil dilation by encoding trial direction
ret_max_dir_model <- lmer(max_pup ~ originTrialDir + (1|participant_id), data = pupil_acc_retrieval)
summary(ret_max_dir_model)


###Stats: Retrieval Pupil Dilation X Recall Accuracy

# 1. Does mean dilation during retrieval predict accuracy?
acc_by_ret_dilation <- glmer(is_correct ~ mean_pup + (1|participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_retrieval)
summary(acc_by_ret_dilation)

# Visualize it
plot_model(acc_by_ret_dilation, type = "pred")
# For now, seems to not have an influence. 

# 2. Does maximum dilation during retrieval predict accuracy?
ret_acc_by_max_dilation <- glmer(is_correct ~ max_pup + (1| participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_retrieval)
summary(ret_acc_by_max_dilation)

# Visualize it
plot_model(ret_acc_by_max_dilation, type = "pred")
# For now, seems to not have an influence. 
 

### Stats: Dilation at retrieval and accuracy by original trial direction

# Does mean dilation during retrieval change by trial direction (and)
ret_td_mean_dilation <- glmer(is_correct ~ mean_pup * originTrialDir + (1|participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_retrieval)
summary(ret_td_mean_dilation)

# Visualize it
plot_model(ret_td_mean_dilation, type = "int")

# What about maximum dilation?
ret_td_max_dilation <- glmer(is_correct ~ max_pup * originTrialDir + (1| participant_id), family = binomial(link = "logit"), control = glmerControl(optimizer="bobyqa"), data = pupil_acc_retrieval)
summary(ret_td_max_dilation)

# Visualize it
plot_model(ret_td_max_dilation, type = "int")
 

#3. Gaze patterns and accuracy
###Rolling averages of accurate trials

# Now moving away from mean/maximum pupil kind of dataframes and going back to gaze locations!
ret_acc_merge <- ret_data_relative %>%
  left_join(select(all_recall_clean, participant_id, TRIAL_INDEX, encoding_order, encoding_position, orderResponse, is_correct, originEncodingTrial, originTrialDir),  by = c("participant_id", "TRIAL_INDEX"))

# We want gaze data to be numeric
ret_acc_merge$LEFT_GAZE_X <- as.numeric(ret_acc_merge$LEFT_GAZE_X)
ret_acc_merge$LEFT_GAZE_Y <- as.numeric(ret_acc_merge$LEFT_GAZE_Y)

#using a "pre-decision" phase, for which for one second participants see a blank screen.
preDecision <- ret_acc_merge %>%
  select(-c(TIMESTAMP, Timebin, triplet1, triplet2, triplet3, newMessage, trialDirection, trialOrder, eTrials, encoding_order.y)) %>%
  rename(encoding_order = encoding_order.x)
  
preDecision <- preDecision %>%
  filter(new_time > 3450, new_time < 4550, 
         LEFT_GAZE_X >= 0, LEFT_GAZE_X <= 1024, 
         LEFT_GAZE_Y >= 0, LEFT_GAZE_Y <= 768)

# Bins of 5 will give us averages over a 1/8th of a second. 
retrieval_mean_gaze <- preDecision %>%
  arrange(participant_id, TRIAL_INDEX, new_time) %>%
  group_by(participant_id, TRIAL_INDEX, encoding_position) %>%  # Group by trial and direction/location
  mutate(
    rolling_gaze_x = rollmean(LEFT_GAZE_X, k = 5, fill = NA, align = "center"),
    rolling_gaze_y = rollmean(LEFT_GAZE_Y, k = 5, fill = NA, align = "center")
  ) %>%
  drop_na(rolling_gaze_x, rolling_gaze_y) %>%
  ungroup()

summary(retrieval_mean_gaze)
retrieval_mean_gaze$encoding_position <-as.factor(retrieval_mean_gaze$encoding_position)

# Plot
# Correct trials, group-level:
ggplot(data = retrieval_mean_gaze %>%
         filter(is_correct == 1, !is.na(rolling_gaze_x), !is.na(new_time), !is.na(participant_id)) %>%
         group_by(new_time, encoding_position) %>%
         summarize(average_gaze_x = mean(rolling_gaze_x, na.rm = TRUE)), 
       aes(x = new_time, y = average_gaze_x, color = encoding_position)) +
  geom_line(aes(color = encoding_position)) + 
  geom_smooth(method = "loess", se = FALSE) + 
  labs(
    title = "Gaze X Location of Correct Retrieval Trials",
    x = "Time (ms)",
    y = "Gaze X") + theme_Publication()

# Incorrect trials, group-level:
ggplot(data = retrieval_mean_gaze %>%
         filter(is_correct == 0, !is.na(rolling_gaze_x), !is.na(new_time), !is.na(participant_id)) %>%
         group_by(new_time, encoding_position) %>%
         summarize(average_gaze_x = mean(rolling_gaze_x, na.rm = TRUE)), 
       aes(x = new_time, y = average_gaze_x, color = encoding_position)) +
  geom_line(aes(color = encoding_position)) + 
  geom_smooth(method = "loess", se = FALSE) + 
  labs(
    title = "Gaze X Location of Inorrect Retrieval Trials",
    x = "Time (ms)",
    y = "Gaze X") + theme_Publication()


#Gaze patterns by encoding order and location

pos_GazeX <- preDecision %>%
  filter(is_correct == 1) %>%
  group_by(TRIAL_INDEX, encoding_position, participant_id, block, originTrialDir) %>%
  summarise(max_x = max(LEFT_GAZE_X), mean_x = mean(LEFT_GAZE_X), x_sd = sd(LEFT_GAZE_X), x_length = length(LEFT_GAZE_X), 
            x_sem = x_sd/sqrt(x_length), 
            upper_CI = mean_x + qt(1 - (0.05 / 2), x_length - 1) * x_sem,
            lower_CI = mean_x - qt(1 - (0.05 / 2), x_length - 1) * x_sem) %>%  drop_na()

# By encoding order and trial direction:
order_GazeX <- preDecision %>%
  filter(is_correct == 1) %>%
  group_by(TRIAL_INDEX, encoding_order, participant_id, block, originTrialDir) %>%
  summarise(max_x = max(LEFT_GAZE_X), mean_x = mean(LEFT_GAZE_X), x_sd = sd(LEFT_GAZE_X), x_length = length(LEFT_GAZE_X), 
            x_sem = x_sd/sqrt(x_length), 
            upper_CI = mean_x + qt(1 - (0.05 / 2), x_length - 1) * x_sem,
            lower_CI = mean_x - qt(1 - (0.05 / 2), x_length - 1) * x_sem) %>%  drop_na()

# Participant-level:
# By encoding position (location) and trial direction:
summary_pos_GazeX <- preDecision %>%
  filter(is_correct == 1) %>%
  group_by(encoding_position, participant_id, block, originTrialDir) %>%
  summarise(mean_x = mean(LEFT_GAZE_X), sd_x = sd(LEFT_GAZE_X), x_length = length(LEFT_GAZE_X))

# By encoding order and trial direction:
order_GazeX <- preDecision %>%
  filter(is_correct == 1) %>%
  group_by(TRIAL_INDEX, encoding_order, participant_id, block, originTrialDir) %>%
  summarise(max_x = max(LEFT_GAZE_X), mean_x = mean(LEFT_GAZE_X), x_sd = sd(LEFT_GAZE_X), x_length = length(LEFT_GAZE_X), 
            x_sem = x_sd/sqrt(x_length), 
            upper_CI = mean_x + qt(1 - (0.05 / 2), x_length - 1) * x_sem,
            lower_CI = mean_x - qt(1 - (0.05 / 2), x_length - 1) * x_sem) %>%  drop_na()

 
##Stats: Retrieval Gaze Location X Encoding Order and Position

# use mean gaze location over the blank screen phase for correct trials:
lm_gazex_data <- sub_ret_gaze_corr_summary %>% filter(is_correct ==1)

# encoding order and gaze x at recall:
meanx_order <- lmer(mean_x~encoding_order + (1|participant_id), data = lm_gazex_data)
summary(meanx_order)

# encoding location and gaze x at recall:
meanx_location <- lmer(mean_x~encoding_position + (1|participant_id), data = lm_gazex_data)
summary(meanx_location)

# encoding order and location and gaze x at recall:
meanx_loc_order <- lmer(mean_x~encoding_position*encoding_order + (1|participant_id), data = lm_gazex_data)
 