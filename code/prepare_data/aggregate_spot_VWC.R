# calculate treatment effects compared to control soil moisture

rm(list = ls())
library( tidyverse)
library(lubridate)
library(sheepweather)

# input ---------------------------------------------------- #
seasons <- read.csv('data/season_table.csv')

daily_clim <- read_csv('data/temp/daily_station_dat_rainfall.csv') 
  # comes from 'make_rainfall.R'

spotVWC <- usses_spot_sm # comes from package

# output ---------------------------------------------------- #

outfile <- 'data/temp/spotVWC.csv'

# ---------------------------------------------------- #

spotVWC <-
  spotVWC %>%
  mutate( month = month( date) ) %>%
  left_join(seasons, by = 'month')

spot_weights <-
  spotVWC %>%
  group_by( date, PrecipGroup ) %>%
  summarise( weight = n())

spotVWC <- 
  spotVWC %>% 
  left_join(daily_clim, by = 'date')

spotVWC <-
  spotVWC %>%
  group_by( season, date, PrecipGroup, rainfall, Treatment ) %>%
  summarise( avg_VWC = mean(VWC, na.rm = TRUE)) %>%
  group_by(PrecipGroup) %>%
  mutate( avg_VWC = scale(avg_VWC, 
                          mean(avg_VWC[Treatment == 'Control'], na.rm = T), 
                          sd(avg_VWC[Treatment == 'Control'], na.rm = T))) %>%  # scale within Precip Group and Depth
  spread( Treatment, avg_VWC) %>%
  mutate( Drought = Drought - Control, Irrigation = Irrigation - Control ) %>%
  arrange( PrecipGroup, date)

spotVWC <- 
  spotVWC %>% 
  left_join(spot_weights, by = c('date', 'PrecipGroup'))


write_csv(spotVWC, file = outfile)

