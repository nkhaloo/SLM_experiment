procedure getPitch
	
######### Calculate mean f0 for each sub-interval#########
			analysis_points_time_step = 0.01

			select 'soundid'
			mean_intensity = Get intensity (dB)

			noprogress To Pitch... 0 f0_minimum f0_maximum
			pitchid = selected("Pitch")

			#### GET OVERALL MEAN / SD F0 / MAX F0 #########
			overall_mean_f0 = Get mean... 0.0 0.0 Hertz
			overall_sd_f0 = Get standard deviation... 0.0 0.0 Hertz
			max_f0 = Get maximum... 0.0 0.0 Hertz Parabolic
								
			###########################################################################################
			total = 0
         	number = 0

			intvl_num = 1
      		position  = start

			########### Within each interval, take f0 measurements every 0.01 s interval ###########
    		while position <= end
					
							while position < start + intvl_num * interval
							select 'pitchid'
							hertz  = Get value at time... position Hertz Linear
		
								average$ = ""

           						if hertz = undefined
	         					 	# do nothing
									average$ = ""
            						else
                  						total  = total + hertz
                  						number = number + 1
            					endif
								position = position + analysis_points_time_step
         						endwhile

      		
							# Calculate mean & median
							average  = total / number

							if total = 0
								average$ = ""
        						else
									average$ = fixed$(average, 3)
							endif



							if intvl_num <= numintervals
					
								selectObject: "Table acoustic_measurements"
								Set string value... table_row_counter Mean_f0_Interval_'intvl_num' 'average'
								select 'pitchid'

							endif

         						intvl_num = intvl_num + 1

						endwhile


endproc