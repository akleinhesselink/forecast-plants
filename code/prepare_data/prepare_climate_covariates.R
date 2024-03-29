#####################################################################################
#
# Make climate variables from seasonal climate 
#
#####################################################################################
library(dplyr)
library(zoo)

rm(list = ls() )

# ------- load files ------------------------------------------------------------------ 

seasonal_clim <- read_csv('data/temp/seasonal_climate.csv')
seasonal_VWC  <- read_csv('data/temp/seasonal_VWC.csv')

# ------- output ------------------------------------------------------------------ 

outfile = 'data/temp/all_clim_covs.csv'

# ------ calculate seasonal lags -----------------------------------------------------# 
#
#   Variable names follow these conventions: 
#   
#     First letter gives variable type: 
#       "P" is cumulative precipitation
#       "T" is average mean monthly temperature
#
#     Letters after the first period give the season aggregation window:
#
#       w  = winter (Q1) 
#       sp = spring (Q2)
#       su = summer (Q3)
#       f  = fall   (Q4)
#       a  = annual (Q1-4)
#
#     e.g. "P.sp" is the cumulative precipitation of the spring season and "P.w.sp" is
#     the cumulative precipitation of the winter and spring. 
#   
#     Number after the second period indicates the year of the transition, For example, 
#     "P.sp.0" gives the cumulative precipitation of year preceding the transition. 
#     Whereas "T.f.w.1" gives the average temperature of the fall and winter 
#     preceding the second year of the transition. "0" refers to year before first year, 
#     i.e. "lag effect" (sensu Adler). 
#
# -------------------------------------------------------------------------------------# 
seasonal_VWC$season <- factor( seasonal_VWC$season, c('winter', 'spring', 'summer', 'fall'), ordered = T)
seasonal_clim$season <- factor( seasonal_clim$season, c('winter', 'spring', 'summer', 'fall'), ordered = T)

seasonal_clim <- 
  seasonal_clim %>% 
  rename("year" = YEAR)

q_VWC <- 
  seasonal_VWC %>% 
  spread(Treatment, avg) %>% 
  mutate( Drought = ifelse( year < 2012, Control, Drought  ),         # assign treatments prior to 2012 with Control level
          Irrigation = ifelse(year < 2012, Control, Irrigation)) %>% 
  gather( Treatment, avg, Control:Irrigation) %>% 
  ungroup() %>% 
  group_by(Treatment) %>% 
  arrange(Treatment, year, season) %>%
  mutate(VWC.sp.1 = avg, 
         VWC.sp.0 = lag( VWC.sp.1, 4),
         VWC.su.1 = lag(avg, 3),
         VWC.su.0 = lag(VWC.su.1, 4),
         VWC.f.1  = lag(avg, 2), 
         VWC.f.0  = lag(VWC.f.1, 4), 
         VWC.a.1 = rollapply(avg, 4,  'mean', na.rm  = T, align = 'right', fill = NA), 
         VWC.a.0 = lag(VWC.a.1, 4), 
         VWC.f.w.sp.1 = rollapply(avg, 3, 'mean', na.rm = T, align = 'right', fill = NA), 
         VWC.sp.su.f.0 = lag(VWC.f.w.sp.1, 2)) %>% 
  filter( season == 'spring') %>%                                           # plants are measured at the end of spring each year 
  dplyr::select( Treatment, Period, year, season, contains('0')) %>%
  ungroup() %>% 
  gather( var, val, starts_with('VWC')) %>% 
  filter( !is.na(val)) %>%
  spread( var, val) 

q_precip <- 
  seasonal_clim %>% 
  filter( var == 'PRCP_ttl') %>%
  group_by(Treatment) %>% 
  arrange(Treatment, year, season) %>%
  mutate(P.f.w.sp.1 = rollsum(val, 3, align = 'right', fill = NA), 
         P.f.w.sp.0 = lag(P.f.w.sp.1, 4),
         P.a.1      = rollsum(val, 4, align = 'right', fill = NA),
         P.a.0      = lag(P.a.1, 4),
         P.su.1 = lag(val, 3),                 
         P.su.0 = lag(P.su.1, 4), 
         P.su.l = lag(P.su.0, 4), 
         P.w.sp.1 = rollsum(val, 2, align = 'right', fill = NA), 
         P.sp.su.0 = lag(P.w.sp.1, 3), 
         P.f.w.sp.1 = rollsum(val, 3, na.rm = T, align = 'right', fill = NA), 
         P.sp.su.f.0 = lag(P.f.w.sp.1, 2)) %>% 
  filter( season == 'spring') %>% # plants are measured at the end of spring each year 
  dplyr::select( Treatment, Period, year, season, starts_with("P"))

q_temp <- 
  seasonal_clim %>% 
  filter( var == 'TAVG_avg' ) %>% 
  group_by(Treatment) %>% 
  arrange(Treatment, year, season) %>% 
  mutate( T.a.1  = rollmean(val, 4, align = 'right', fill = NA), 
          T.a.0  = lag(T.a.1, 4),
          T.sp.1 = val, 
          T.sp.0 = lag(T.sp.1, 4),
          T.su.1 = lag(val, 3), 
          T.su.0 = lag(T.su.1, 4), 
          T.f.1 = lag(val, 2), 
          T.f.0 = lag(T.f.1, 4), 
          T.w.1 = lag(val, 1), 
          T.f.w.sp.1 = rollapply(val, 3, 'mean', na.rm = T, align = 'right', fill = NA), 
          T.sp.su.f.0 = lag(T.f.w.sp.1, 2)) %>% 
  filter( season == 'spring') %>% 
  dplyr::select( Treatment, Period, year, season, starts_with("T."))

allClim <- 
  q_precip %>% 
  left_join ( q_temp, by = c('Treatment', 'Period', 'season', 'year')) %>% 
  right_join ( q_VWC, by = c('Treatment', 'Period', 'season', 'year')) %>% 
  arrange( Treatment, year) 

NA_index <- apply( allClim, 1 , function(x) any(is.na(x)))

allClim <- allClim[-NA_index, ]

# adjust years so that they match the demographic data sets ------------------------------------------------------------------# 

allClim$year <- allClim$year - 1 # adjust to match assignment of year 0 as the reference year in demographic data sets

# ----------------------------------------------------------------------------------------------------------------------------# 

# -- calculate interactions --------------------------------------------------------------#

allClim <- data.frame(allClim)

# include interactions between temperature and VWC for each season
( names( allClim))

VWCvars <- which(is.element(substring(names(allClim),1,2),"VW")==T)
tmp_dat <- matrix(NA,nrow(allClim),length(VWCvars))
colnames(tmp_dat) <- paste0("VWCxT.",substring(names(allClim)[VWCvars],5))

for(i in 1:length(VWCvars)){
  do_season <- substring(names(allClim)[VWCvars[i]],5)
  iT <- which(names(allClim)==paste0("T.",do_season))
  names(allClim)  
  do_season
  tmp_dat[,i] <- allClim[,VWCvars[i]]*allClim[,iT]
  
  tmp_dat[, i]
}

allClim <- cbind(allClim,tmp_dat)

# ---- output ----------------------------------------------------------------------------# 

write_csv( allClim , file = outfile ) 
