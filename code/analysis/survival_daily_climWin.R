rm(list = ls())

library(tidyverse)
library(lme4)
library(zoo)
library(lubridate)
library(climwin)
source('code/analysis/functions.R')

last_year <- 2010 # last year of training data, everything earlier is used 

# ClimWin Window Settings Monthly
sp_list <- c('ARTR', 'HECO', 'POSE', 'PSSP')

window_open_max <- 24
window_open_min <- 1
window_exclude_dur <- 1
window_exclude_max <- 5

#species <- 'ARTR' # for testing 

# Climate and VWC data  ------------------- # 
quad_info <- read_csv( file = 'data/quad_info.csv')
daily_weather <- 
  read_csv('data/temp/daily_weather_for_models.csv') %>% 
  filter( Treatment == 'Control') %>% 
  filter( year <= last_year)

species <- 'ARTR'
## ------------------------------------------------- 
for(species in sp_list){ 
  
  survival <- prep_survival_for_climWin(species, 
                                        last_year = last_year, 
                                        quad_info = quad_info)
  
  # m_baseline <- glmer(
  #   survives ~ area0*climate + W.intra + (1|year),
  #   data = survival,
  #   family = 'binomial',
  #   control = glmerControl(optimizer = 'bobyqa'))
  # 
  # model_type <- "mer"
  # 
  m_baseline <- glm( survives ~ 1 + area0*climate + W.intra, data = survival, family = 'binomial')
  model_type <- "glm"

  write_csv( survival, paste0( 'data/temp/', species, '_ClimWin_Survival_data.csv'))
  write_rds( m_baseline, paste0( 'output/survival_models/', species, '_survival_', model_type, '_baseline.rds'))
  
  survivesWin <- slidingwin(xvar = list(VWC_scaled = daily_weather$VWC_scaled, 
                                        #TMAX_scaled = daily_weather$TMAX_scaled, 
                                        #TAVG_scaled = daily_weather$TAVG_scaled, 
                                        TMIN_scaled = daily_weather$TMIN_scaled),
                              cdate = daily_weather$date_reformat,
                              bdate = survival$date_reformat,
                              baseline = m_baseline, 
                              cinterval = 'month',
                              range = c(window_open_max, window_open_min),
                              type = "absolute", 
                              refday = c(15, 06),
                              stat = 'mean', 
                              func = c('lin'), cv_by_cohort = T, ncores = 8)
  
  # Refit with the best climate var in baseline 
  addVars_list <- addVars(survivesWin, survival, fitStat = 'deltaLogLoss')
  
  m_baseline <- update( m_baseline, paste0(  ". ~ . + area0*", addVars_list$bestVar), 
                        data = addVars_list$data2)
  
  newVars <- as.list( daily_weather[, addVars_list$addVars])  
  
  survivesWin2 <- slidingwin(xvar = newVars,
                           cdate = daily_weather$date_reformat,
                           bdate = addVars_list$data2$date_reformat,
                           baseline = m_baseline,
                           cinterval = 'month',
                           range = c(window_open_max, window_open_min),
                           #exclude = c(window_exclude_dur, window_exclude_max),
                           type = "absolute", refday = c(15, 06),
                           stat = 'mean', 
                           func = c('lin'), cv_by_cohort = T, ncores = 8)
  
  out_obj_name <- paste(species, 'survival', 'monthly_ClimWin', sep = '_')
  
  out <- list( survivesWin, survivesWin2 )
  names(out ) <- c('ClimWinFit1', 'ClimWinFit2')
  
  assign( 
    out_obj_name, 
    out
  )
  
  save(list = out_obj_name, 
       file = paste0( "output/survival_models/", species, "_survival_", model_type, "_monthly_ClimWin.rda"))
  
}



for(species in sp_list){ 
  
  survival <- prep_survival_for_climWin(species, 
                                        last_year = last_year, 
                                        quad_info = quad_info)
  
  # m_baseline <- glmer(
  #   survives ~ area0 + W.intra + (1|year),
  #   data = survival,
  #   family = 'binomial',
  #   control = glmerControl(optimizer = 'bobyqa'))
  # 
  # model_type <- "mer"
  
  m_baseline <- glm( survives ~ 1 + area0*climate + W.intra, data = survival, family = 'binomial')
  model_type <- "glm"
  #write_csv( survival, paste0( 'data/temp/', species, '_ClimWin_Survival_data.csv'))
  write_rds( m_baseline, paste0( 'output/survival_models/', species, '_survival_no_intxn_', model_type, '_baseline.rds'))
  
  survivesWin <- slidingwin(xvar = list(VWC_scaled = daily_weather$VWC_scaled, 
                                        TMAX_scaled = daily_weather$TMAX_scaled, 
                                        TAVG_scaled = daily_weather$TAVG_scaled, 
                                        TMIN_scaled = daily_weather$TMIN_scaled),
                            cdate = daily_weather$date_reformat,
                            bdate = survival$date_reformat,
                            baseline = m_baseline, 
                            cinterval = 'month',
                            range = c(window_open_max, window_open_min),
                            type = "absolute", 
                            refday = c(15, 06),
                            stat = 'mean', 
                            func = c('lin'), cv_by_cohort = T, ncores = 8)
  
  addVars_list <- addVars(survivesWin, survival, fitStat = 'deltaLogLoss')
  
  m_baseline <- update( m_baseline, paste0(  ". ~ . + ", addVars_list$bestVar), 
                        data = addVars_list$data2)
  
  newVars <- as.list( daily_weather[, addVars_list$addVars])  
  
  survivesWin2 <- slidingwin(xvar = newVars,
                             cdate = daily_weather$date_reformat,
                             bdate = addVars_list$data2$date_reformat,
                             baseline = m_baseline,
                             cinterval = 'month',
                             range = c(window_open_max, window_open_min),
                             #exclude = c(window_exclude_dur, window_exclude_max),
                             type = "absolute", refday = c(15, 06),
                             stat = 'mean', 
                             func = c('lin'), cv_by_cohort = T, ncores = 8)
  
  out_obj_name <- paste(species, 'survival', 'no_intxn_monthly_ClimWin', sep = '_')
  
  out <- list( survivesWin, survivesWin2 )
  names(out ) <- c('ClimWinFit1', 'ClimWinFit2')
  
  assign( 
    out_obj_name, 
    out
  )
  
  save(list = out_obj_name, 
       file = paste0( "output/survival_models/", species, "_survival_no_intxn_", model_type, "_monthly_ClimWin.rda"))
  
}
