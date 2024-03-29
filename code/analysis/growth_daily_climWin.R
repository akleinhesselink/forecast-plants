rm(list = ls())
library(tidyverse)
library(lubridate)
library(climwin)
library(lme4)
library(optimx)
library(dfoptim)

# LMER optimization options
control_lmer = lmerControl(
  optimizer = "optimx",
  calc.derivs = FALSE,
  optCtrl = list(
    method = "nlminb",
    starttests = FALSE,
    kkt = FALSE
  )
)
control_lmer$optCtrl$eval.max <- 1e8
control_lmer$optCtrl$iter.max <- 1e8


source('code/analysis/functions.R')

# Variables -------------------------------- : 
last_year <- 2010 # last year of training data, everything before and including this year is used 
sp_list <- c('ARTR', 'HECO', 'POSE', 'PSSP')

# ClimWin Window Settings Monthly
window_open_max <- 24
window_open_min <- 1
window_exclude_dur <- 1
window_exclude_max <- 5

size_cutoff <- -1 # size division for big/small 

# Climate and VWC data  ------------------- # 
quad_info <- read_csv( file = 'data/quad_info.csv')
daily_weather <- 
  read_csv('data/temp/daily_weather_for_models.csv') %>% 
  filter( Treatment == 'Control') %>% 
  filter( year <= last_year)
species <- 'ARTR'
## ------------------------------------------------- 
for(species in sp_list){ 
  # loop Species 
  # 1. Find best univariate climate model 
  # 2. Redo ClimWin model selection with additional variable
  #     a. When best climate variable is temperature add VWC window 
  #     b. When best climate variable is VWC add temperature window 
  # 3. Save top model and data 
  
  growth <- prep_growth_for_climWin(species, last_year = last_year, quad_info = quad_info, size_cutoff = size_cutoff)
  
  ##baseline model for growth/size
  m_baseline <- lmer( area ~ area0*climate + W.intra + (1|year/Group),
                       data = growth,
                       REML = F,
                       control = control_lmer)

  model_type <- "mer"
  # m_baseline <- lm( area ~ area0*climate + W.intra, data = growth)
  # model_type <- "lm"
  # 
  write_csv( growth, paste0( 'data/temp/', species, '_ClimWin_Growth_data.csv'))
  write_rds( m_baseline, paste0( 'output/growth_models/', species, '_growth_', model_type, '_baseline.rds'))
  
  growthWin <- slidingwin(xvar = list(TMAX_scaled = daily_weather$TMAX_scaled, 
                                           #TAVG_scaled = daily_weather$TAVG_scaled,
                                           #TMIN_scaled = daily_weather$TMIN_scaled, 
                                           VWC_scaled = daily_weather$VWC_scaled),
                               cdate = daily_weather$date_reformat,
                               bdate = growth$date_reformat,
                               baseline = m_baseline,
                               cinterval = "month",
                               range = c(window_open_max, window_open_min),
                               #exclude = c(window_exclude_dur, window_exclude_max),                              
                               type = "absolute", refday = c(15, 06), 
                               stat = 'mean', 
                               func = c('lin'), 
                          cv_by_cohort = TRUE, ncores = 8)

  # Refit with best variable added to baseline
  addVars_list <- addVars(growthWin, data1 = growth, responseVar = 'area', fitStat = 'deltaMSE')
  
  m_baseline <- update( m_baseline, paste0(  ". ~ . + area0*", addVars_list$bestVar), 
                             data = addVars_list$data2)
  
  newVars <- as.list( daily_weather[, addVars_list$addVars])
  
  growthWin2 <- slidingwin(xvar = newVars,
             cdate = daily_weather$date_reformat,
             bdate = addVars_list$data2$date_reformat,
             baseline = m_baseline,
             cinterval = 'month',
             range = c(window_open_max, window_open_min),
             #exclude = c(window_exclude_dur, window_exclude_max),
             type = "absolute", refday = c(15, 06),
             stat = 'mean', 
             func = c('lin'),
             cv_by_cohort = TRUE, ncores = 4)
  
  out_obj_name <- paste(species, 'growth', 'monthly_ClimWin', sep = '_')
  
  out <- list( growthWin, growthWin2 )
  names(out ) <- c('ClimWinFit1', 'ClimWinFit2')
  
  assign( 
    out_obj_name, 
    out
  )
  
  save(list = out_obj_name, 
       file = paste0( "output/growth_models/", species, "_growth_", model_type, "_monthly_ClimWin.rda"))
  
}

for(species in sp_list){ 
    
  # Fit models without climate x size interaction 

  growth <- prep_growth_for_climWin(species, last_year = last_year, quad_info = quad_info, size_cutoff = size_cutoff)
  
  m_baseline <- lmer( area ~ area0 + W.intra + (1|year/Group),
                      data = growth,
                      REML = F,
                      control = control_lmer)

  model_type <- "mer"
  # m_baseline <- lm( area ~ area0 + W.intra, data = growth)
  # model_type <- "lm"

  write_rds( m_baseline, paste0( 'output/growth_models/', species, '_growth_no_intxn_', model_type, '_baseline.rds'))
  
  growthWin <- slidingwin(xvar = list(TMAX_scaled = daily_weather$TMAX_scaled, 
                                      #TAVG_scaled = daily_weather$TAVG_scaled,
                                      #TMIN_scaled = daily_weather$TMIN_scaled, 
                                      VWC_scaled = daily_weather$VWC_scaled),
                          cdate = daily_weather$date_reformat,
                          bdate = growth$date_reformat,
                          baseline = m_baseline,
                          cinterval = "month",
                          range = c(window_open_max, window_open_min),
                          #exclude = c(window_exclude_dur, window_exclude_max),                              
                          type = "absolute", refday = c(15, 06), 
                          stat = 'mean', 
                          func = c('lin'), 
                          cv_by_cohort = TRUE, ncores = 8)
  
  # Refit with best variable added to baseline
  addVars_list <- addVars(growthWin, data1 = growth, responseVar = 'area', fitStat = 'deltaMSE')
  
  m_baseline <- update( m_baseline, paste0(  ". ~ . + ", addVars_list$bestVar), 
                        data = addVars_list$data2)
  
  newVars <- as.list( daily_weather[, addVars_list$addVars])
  
  growthWin2 <- slidingwin(xvar = newVars,
                           cdate = daily_weather$date_reformat,
                           bdate = addVars_list$data2$date_reformat,
                           baseline = m_baseline,
                           cinterval = 'month',
                           range = c(window_open_max, window_open_min),
                           #exclude = c(window_exclude_dur, window_exclude_max),
                           type = "absolute", refday = c(15, 06),
                           stat = 'mean', 
                           func = c('lin'), 
                           cv_by_cohort = TRUE, ncores = 8)
  
  out_obj_name <- paste(species, 'growth', 'no_intxn_monthly_ClimWin', sep = '_')
  
  out <- list( growthWin, growthWin2 )
  names(out ) <- c('ClimWinFit1', 'ClimWinFit2')
  
  assign( 
    out_obj_name, 
    out
  )
  
  
  save(list = out_obj_name, 
       file = paste0( "output/growth_models/", species, "_growth_no_intxn_", model_type, "_monthly_ClimWin.rda"))

}