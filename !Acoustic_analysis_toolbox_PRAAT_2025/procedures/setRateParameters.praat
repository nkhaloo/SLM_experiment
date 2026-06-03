procedure setRateParameters

################ (1) Set parameters ################
analysis_points_time_step = 0.01

############### Speech rate ###############

	# From speech rate script
   #	real Silence_threshold_(dB) -25
   #	real Minimum_dip_between_peaks_(dB) 2
   #	real Minimum_pause_duration_(s) 0.3
   #	boolean Keep_Soundfiles_and_Textgrids yes


# shorten variables
silencedb = -25
mindip = 2
showtext = 1
minpause = 0.3



endproc